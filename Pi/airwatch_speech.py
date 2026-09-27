"""Short speech files for AirWatch push notifications; no Apple credentials here.

Run as a separate service: python3 airwatch_speech.py
The existing APNs sender imports attach_spoken_audio only when explicitly enabled.
"""
import http.server
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile
import threading
import time
import wave

MAX_BYTES = 1_200_000
MAX_SECONDS = 25
TTL_SECONDS = 120
_LOCK = threading.Lock()


def cache_directory():
    return Path(os.environ.get("AIRWATCH_SPEECH_CACHE",
                               str(Path.home() / ".airwatch-private/speech")))


def spoken_text(event):
    kind = event.get("event_type", "")
    if kind.startswith("health_"):
        labels = {"gps": "GPS", "1090": "ten ninety receiver", "978": "nine seventy eight receiver"}
        component = labels.get(event.get("component"), "Receiver")
        return component + (" signal lost." if kind == "health_fault" else " signal restored.")
    identity = str(event.get("registration") or event.get("flight") or event.get("hex") or "").strip()
    # Separate letters and digits so callsigns aren't pronounced as invented words.
    identity = " ".join(identity[:20])
    label = str(event.get("agency") or (
        "Helicopter" if event.get("airframe_class") == "helicopter" else "Aircraft"))[:60]
    if kind == "factor_cleared":
        return f"Clear. {label} {identity} is no longer a factor."
    if kind != "factor_entered":
        return None
    details = [f"Traffic. {label} {identity}"]
    clock = event.get("clock_position")
    if clock:
        details.append(f"your {clock} o'clock")
    elif event.get("direction"):
        directions = {"N": "north", "NE": "northeast", "E": "east", "SE": "southeast",
                      "S": "south", "SW": "southwest", "W": "west", "NW": "northwest"}
        details.append(directions.get(str(event["direction"]), str(event["direction"])))
    if event.get("distance_mi") is not None:
        details.append(f'{float(event["distance_mi"]):.1f} miles')
    if event.get("altitude_ft") is not None:
        details.append(f'{round(float(event["altitude_ft"]))} feet')
    if event.get("movement"):
        details.append(str(event["movement"])[:40])
    return ", ".join(details) + "."


def valid_wave(path):
    if not 44 <= path.stat().st_size <= MAX_BYTES:
        return False
    with wave.open(str(path), "rb") as sound:
        return (sound.getcomptype() == "NONE" and sound.getnchannels() == 1
                and sound.getsampwidth() == 2 and 8000 <= sound.getframerate() <= 48000
                and 0 < sound.getnframes() / sound.getframerate() <= MAX_SECONDS)


def attach_spoken_audio(event, alert):
    """Best effort: any failure leaves the original alert and chime unchanged."""
    if os.environ.get("AIRWATCH_SPOKEN_PUSH") != "1":
        return
    try:
        text = spoken_text(event)
        if not text or len(text) > 350:
            return
        with _LOCK:
            folder = cache_directory()
            folder.mkdir(parents=True, mode=0o700, exist_ok=True)
            # Expired links become unusable even if cleanup hasn't run yet.
            for old in folder.glob("*.wav"):
                if time.time() - old.stat().st_mtime > TTL_SECONDS:
                    old.unlink(missing_ok=True)
            # Bound storage and queued speech during an event storm.
            if len(list(folder.glob("*.wav"))) >= 64:
                return
            with tempfile.TemporaryDirectory(dir=folder) as temporary:
                source = Path(temporary) / "speech.wav"
                subprocess.run(["espeak-ng", "-v", "en-us", "-s", "175", "-w", str(source), "--stdin"],
                               input=text.encode("utf-8"), stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=4, check=True)
                if not valid_wave(source):
                    raise ValueError("invalid speech audio")
                name = secrets.token_hex(16) + ".wav"
                destination = folder / name
                os.chmod(source, 0o600)
                os.replace(source, destination)
        # A short-lived random capability URL, not the pairing secret or APNs token.
        # Kept on the same private hotspot as the existing AirWatch HTTP API.
        alert["airwatch_audio_url"] = "http://172.20.10.2:8100/audio/" + name
        alert["aps"]["mutable-content"] = 1
        print("SPOKEN_PUSH audio prepared", flush=True)
    except Exception:
        print("SPOKEN_PUSH unavailable; keeping notification chime", flush=True)


class SpeechHandler(http.server.BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(3)

    def log_message(self, *args):
        pass  # URL paths are temporary access tokens; don't log them.

    def do_GET(self):
        match = re.fullmatch(r"/audio/([0-9a-f]{32}\.wav)", self.path)
        if not match:
            self.send_error(404)
            return
        path = cache_directory() / match.group(1)
        try:
            if path.is_symlink() or time.time() - path.stat().st_mtime > TTL_SECONDS:
                self.send_error(404)
                return
            with path.open("rb") as stream:
                data = stream.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES:
                self.send_error(404)
                return
        except OSError:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    http.server.HTTPServer(("0.0.0.0", 8100), SpeechHandler).serve_forever()

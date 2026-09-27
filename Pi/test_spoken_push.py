import copy
import http.client
import http.server
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import wave

import airwatch_speech as speech


def make_wave(path, seconds=1, channels=1):
    with wave.open(str(path), "wb") as output:
        output.setnchannels(channels)
        output.setsampwidth(2)
        output.setframerate(22050)
        output.writeframes(b"\0\0" * int(22050 * seconds) * channels)


class SpeechTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.folder = Path(self.temp.name)
        self.env = patch.dict(os.environ, {
            "AIRWATCH_SPOKEN_PUSH": "1",
            "AIRWATCH_SPEECH_CACHE": str(self.folder),
        })
        self.env.start()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(self.env.stop)
        self.event = {"event_type": "factor_entered", "registration": "N123",
                      "distance_mi": 1.2, "altitude_ft": 900, "clock_position": 2,
                      "movement": "closing"}
        self.alert = {"aps": {"sound": "default", "alert": {"title": "Traffic"}}}

    def test_spoken_details_and_clear(self):
        text = speech.spoken_text(self.event)
        for value in ("N 1 2 3", "1.2 miles", "900 feet", "2 o'clock", "closing"):
            self.assertIn(value, text)
        self.event["event_type"] = "factor_cleared"
        self.assertIn("no longer a factor", speech.spoken_text(self.event))

    def test_audio_prepared_and_valid(self):
        def fake_run(command, **kwargs):
            make_wave(Path(command[command.index("-w") + 1]))
        with patch.object(speech.subprocess, "run", side_effect=fake_run):
            speech.attach_spoken_audio(self.event, self.alert)
        self.assertEqual(self.alert["aps"]["mutable-content"], 1)
        name = self.alert["airwatch_audio_url"].rsplit("/", 1)[1]
        self.assertRegex(name, r"^[0-9a-f]{32}\.wav$")
        self.assertTrue(speech.valid_wave(self.folder / name))
        self.assertEqual(self.alert["aps"]["sound"], "default")

    @unittest.skipUnless(shutil.which("espeak-ng"), "espeak-ng not installed locally")
    def test_real_espeak_generation(self):
        speech.attach_spoken_audio(self.event, self.alert)
        self.assertEqual(self.alert["aps"].get("mutable-content"), 1)
        name = self.alert["airwatch_audio_url"].rsplit("/", 1)[1]
        self.assertTrue(speech.valid_wave(self.folder / name))

    def test_failures_preserve_chime(self):
        original = copy.deepcopy(self.alert)
        with patch.object(speech.subprocess, "run", side_effect=FileNotFoundError):
            speech.attach_spoken_audio(self.event, self.alert)
        self.assertEqual(self.alert, original)
        with patch.object(speech.subprocess, "run", side_effect=subprocess.TimeoutExpired("espeak", 4)):
            speech.attach_spoken_audio(self.event, self.alert)
        self.assertEqual(self.alert, original)

    def test_disabled_no_synthesis(self):
        os.environ["AIRWATCH_SPOKEN_PUSH"] = "0"
        with patch.object(speech.subprocess, "run") as run:
            speech.attach_spoken_audio(self.event, self.alert)
            run.assert_not_called()

    def test_reject_long_or_stereo_audio(self):
        p = self.folder / "test.wav"
        make_wave(p, seconds=26)
        self.assertFalse(speech.valid_wave(p))
        make_wave(p, channels=2)
        self.assertFalse(speech.valid_wave(p))

    def test_http_valid_expired_and_traversal(self):
        name = "a" * 32 + ".wav"
        path = self.folder / name
        make_wave(path)
        server = http.server.HTTPServer(("127.0.0.1", 0), speech.SpeechHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            def get(resource):
                connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=3)
                connection.request("GET", resource)
                response = connection.getresponse()
                data = response.read()
                result = response.status
                connection.close()
                return result, data
            self.assertEqual(get("/audio/" + name)[0], 200)
            self.assertEqual(get("/audio/../apns.env")[0], 404)
            self.assertEqual(get("/audio/" + name + "?anything")[0], 404)
            os.utime(path, (time.time() - 121, time.time() - 121))
            self.assertEqual(get("/audio/" + name)[0], 404)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_patch_guard_and_idempotence(self):
        target = self.folder / "airwatch_push.py"
        target.write_text("def send_event(event):\n    alert, live = payloads(event, now)\n")
        script = Path(__file__).with_name("prepare_spoken_push.py")
        for _ in range(2):
            subprocess.run([sys.executable, str(script), str(target)], check=True, capture_output=True)
        self.assertEqual(target.read_text().count("from airwatch_speech import"), 1)
        target.write_text("unrecognized = True\n")
        result = subprocess.run([sys.executable, str(script), str(target)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), "unrecognized = True\n")


if __name__ == "__main__":
    unittest.main()

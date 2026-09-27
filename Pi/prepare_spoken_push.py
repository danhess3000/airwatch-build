"""Prepare a reviewed change in the Pi working tree. Does not commit or restart."""
from pathlib import Path
import sys

target = Path(sys.argv[1] if len(sys.argv) == 2 else "/opt/airwatch/airwatch_push.py")
old = '    alert, live = payloads(event, now)\n'
new = old + '''    if os.environ.get("AIRWATCH_SPOKEN_PUSH") == "1":
        try:
            from airwatch_speech import attach_spoken_audio
            attach_spoken_audio(event, alert)
        except Exception:
            print("SPOKEN_PUSH unavailable; keeping notification chime", flush=True)
'''
source = target.read_text()
if new in source:
    print("Speech hook already present; no changes.")
    raise SystemExit(0)
if source.count(old) != 1:
    raise SystemExit("Unexpected sender source; stopped without changes.")
updated = source.replace(old, new)
compile(updated, str(target), "exec")
backup = target.with_suffix(".py.before-spoken-push")
with backup.open("x") as f:
    f.write(source)
target.write_text(updated)
print("Speech hook added; backup saved. Review git diff before deploying.")

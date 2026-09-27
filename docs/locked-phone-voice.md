# Spoken alerts while the phone is locked

Status: implementation prepared; not verified on a physical iPhone yet.
Do not treat the earlier successful chime/Live Activity tests as speech validation.

## Design and limits

The Pi renders aircraft details using local espeak-ng into a short PCM WAV.
The ordinary alert carries mutable-content=1 and a temporary audio URL. An iOS
notification service extension downloads it into the app's shared Library/Sounds
directory and tells iOS to use it as the notification sound. It does not try to
start AVSpeechSynthesizer while suspended, play silent keep-alive audio, or use
silent push as a polling mechanism.

Apple documents notification extension custom sounds and shared group sound
storage:
https://developer.apple.com/documentation/usernotifications/unnotificationsound
Apple recommends server-generated speech for this use case:
https://developer.apple.com/forums/thread/810066

The sound must be downloaded before presentation. The extension permits only the
existing Pi address, port 8100, with random 128-bit filenames; no redirects.
Downloads have a 12-second resource limit and a 15-second completion deadline.
PCM audio is limited to 1.2 MB, mono 16-bit, and 25 seconds. Generation times out
after four seconds and preserves the existing chime on failure. Unsupported event
types also retain the chime. Apple delivery, network access, sound permissions,
Silent Mode, Focus, and competing notifications can affect playback. No claim of
guaranteed delivery, silent-switch bypass, Siri speech, or CarPlay behavior.

The helper serves audio only on the local network, like the existing Pi API.
The URLs are unguessable but are not encrypted; trusted hotspot use is required.
They expire after 120 seconds. At most 64 recent files are retained; old files
are cleaned when generating another sound. The extension removes its own cached
sounds after 24 hours when it receives a subsequent sound. No voice cloud service,
pairing secret, APNs key, or device token is exposed through the speech HTTP server.
The phone must remain able to reach the Pi while locked.

## Apple setup (before the next TestFlight archive)

Keep com.danhess.airwatch and com.danhess.airwatch.widget unchanged.
In Apple Developer Certificates, Identifiers & Profiles:
1. Register an App Group: group.com.danhess.airwatch.
2. Enable App Groups for com.danhess.airwatch and assign that group.
   Preserve Push Notifications and Time Sensitive Notifications.
3. Register an explicit App ID: com.danhess.airwatch.speech, description
   "AirWatch Speech". Enable App Groups and assign the same group.
   This is a notification service extension, not a separate App Store listing.
4. The widget doesn't need this group. Keep the existing APNs key/topic.
5. Push the local commit. Compile CI runs Swift tests and the simulator build.
   After signing configuration and compile checks pass, dispatch a NEW TestFlight
   run on main. The workflow verifies the archived extension metadata, production
   APNs entitlement, and shared group entitlements in both signed bundles.

## Pi preparation (separate canonical repo, review before deployment)

Files under Pi/ in this build mirror are a proposed companion change. Nothing
has been copied to /opt/airwatch or /srv/git/airwatch.git automatically.

On the Pi, first inspect git status and current commit in /opt/airwatch. Account
for existing changes, then use a feature branch in that canonical working copy.
Transfer these files into a private staging directory using scp:
- airwatch_speech.py
- prepare_spoken_push.py
- test_spoken_push.py
- airwatch-speech.service

Install espeak-ng with the Pi's package manager:
    sudo apt-get install espeak-ng

Copy airwatch_speech.py and test_spoken_push.py into the working tree. Run the
guarded patch helper against /opt/airwatch/airwatch_push.py. It requires exactly
one known insertion site, saves an exclusive .before-spoken-push backup, never
restarts the service, and refuses unexpected source. Existing sender output and
Live Activity payloads are otherwise unchanged. The feature defaults to OFF.

Review git diff. Run:
    python3 -m unittest discover -p 'test_companion*.py' -v
    python3 -m unittest test_spoken_push -v
    python3 -m py_compile airwatch_push.py airwatch_speech.py

Review and commit the intended source files in the canonical repository through
its normal workflow. Do not add environment files, tokens, WAV files, or the
backup file to Git.

## Pi activation (after installing the updated TestFlight app)

The current service runs as dhess and the current private key/configuration live
in /home/dhess/.airwatch-private. The supplied speech unit assumes those paths.

Install the reviewed airwatch-speech.service in /etc/systemd/system/.
Create the cache directory owned by dhess, mode 0700:
    install -d -m 700 /home/dhess/.airwatch-private/speech

Enable and start the speech server:
    sudo systemctl daemon-reload
    sudo systemctl enable --now airwatch-speech.service

Add only these non-secret lines to the EXISTING private apns.env (avoid duplicate
entries; preserve all current APNs credentials, pairing secret, and Pushover):
    AIRWATCH_SPOKEN_PUSH=1
    AIRWATCH_SPEECH_CACHE=/home/dhess/.airwatch-private/speech

Restart airwatch.service, then confirm BOTH services are active. The speech
service only needs its cache setting and does not load the private APNs env file.
Its loopback/local-network port is 8100; do not forward this port on a router.

Rollback: set AIRWATCH_SPOKEN_PUSH=0 and restart airwatch.service.
Ordinary chime alerts and Live Activity updates continue using the existing code.
The helper service may then be stopped. Do not revoke/delete the working APNs key.

## Acceptance test (required before calling this complete)

1. Install the updated TestFlight build; open once, allow local network access,
   keep notifications/Sounds enabled, and turn Silent Mode off.
2. Confirm GPS/receiver feeds, existing pairing, and foreground speech still work.
3. Keep the phone locked for at least five minutes with no debugger attached.
4. Send a synthetic factor_entered event via the EXISTING loopback test endpoint:
       curl -sS -H 'Content-Type: application/json' \
         -d '{"event_type":"factor_entered"}' http://127.0.0.1:8099/api/test-event
5. Confirm spoken TEST01, direction/clock position, distance, altitude and movement
   on the locked phone. A chime, banner, or HTTP 200 alone is NOT a pass.
6. Send factor_cleared and confirm spoken clearance. Repeat health-fault/recovery
   test fixtures supported by the detector without interrupting real hardware.
7. Verify APNS_ALERT and APNS_LIVEACTIVITY acceptance, card updates, and no duplicate
   foreground audio. Don't publish full journals/credentials or capability URLs.
8. Repeat while another app is foreground, after a phone reboot/unlock, and after
   reconnecting the hotspot. Check burst alerts for stale/overlapping speech.
9. Stop the helper temporarily and confirm the normal notification/chime fallback;
   restart it afterward. Check long/unavailable synthesis also preserves alerts.
10. Measure time from the Pi test event to speech start. CarPlay and audio ducking
    need separate parked-car tests. Record failures and latency, not just passes.

No physical-device speech test has been completed for this implementation.

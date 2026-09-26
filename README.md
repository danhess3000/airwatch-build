# AirWatch iPhone build mirror

This private repository is a build mirror of the iPhone app. The canonical
AirWatch repository remains `/srv/git/airwatch.git` on `hbaseC-AI`;
source snapshot: `main` commit `190c2ee`, plus iOS signing setup.

The Compile workflow is an unsigned compile check. The manual Upload internal
TestFlight build workflow archives and uploads a signed build. In Apple Developer,
register explicit identifiers `com.danhess.airwatch` (enable Push Notifications)
and `com.danhess.airwatch.widget`. In App Store Connect, create an iOS app record
with the first identifier. Generate a Team App Store Connect API key with App
Manager access, and download its `.p8` once.

Add these GitHub repository Actions secrets (Settings > Secrets and variables >
Actions):

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer membership Team ID |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID |
| `ASC_KEY_BASE64` | Base64 of the complete downloaded `.p8` bytes |

On Windows PowerShell, get the last value with:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\path\to\AuthKey_XXXXXXXXXX.p8'))
```

Run Actions > Upload internal TestFlight build > Run workflow. When Apple has
processed the build, add the account holder to an Internal Testing group in
App Store Connect and install via TestFlight on the iPhone. The first signing
run may need Apple signing assets created in the developer account; inspect the
workflow log if it fails.

Do not commit the `.p8`, signing certificate, provisioning profile, APNs key,
pairing code, or Pi configuration. The Pi's APNs sending key is separate from
the App Store Connect key and must remain on the Pi.

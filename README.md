# AirWatch iPhone build mirror

This private repository contains only the iPhone app and its unsigned macOS
compile workflow. The canonical AirWatch repository remains `/srv/git/airwatch.git`
on `hbaseC-AI`; source snapshot: `main` commit `190c2ee`.

No Apple certificate, provisioning profile, APNs key, pairing code, or Pi
configuration belongs in this repository. The unsigned simulator build is a
compile check; it cannot be installed on an iPhone.

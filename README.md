# PrismCam for RootHide Dopamine

Clean-room virtual-camera MVP for an iPhone 11 Pro Max (A13/arm64e) on iOS 16.2.

## Features

- Still-image and looping-video sources selected in the app.
- OBS Virtual Camera input over trusted Wi-Fi through `tools/obs_relay.py`.
- Automatic color synchronization using center-region color averages from the real and virtual frames.
- Manual red, green, and blue gain controls.
- No account server, telemetry, root daemon, CoreTelephony access, or downloaded executable code.
- Four-hour activation lease. Enabling the feature again renews the lease.
- An always-on magenta frame marker and SpringBoard banner while virtual-camera mode is armed.

## Safety boundary

This build is intended for local testing, content production, and accessibility workflows. It deliberately has no hidden mode: the output marker and the SpringBoard indicator cannot be disabled from configuration. Do not use it to misrepresent a live camera feed, defeat identity checks, or access another person's device.

## Architecture

- `app/`: UIKit controller app; stores only local settings and selected media.
- `daemon/`: unprivileged `mobile` daemon; loops local video or accepts paired MJPEG frames from the OBS relay.
- `camera/`: MobileSubstrate hook for `cameracaptured`/`mediaserverd`; performs aspect-fill, color matching, and in-place Core Image rendering.
- `overlay/`: persistent SpringBoard safety banner.
- `shared/`: RootHide-aware paths and configuration.
- `layout/`: launch daemon and package lifecycle scripts.

RootHide uses a randomly named jailbreak root, not a fixed `/var/jb`. The source therefore resolves paths with `jbroot()` and is packaged with `THEOS_PACKAGE_SCHEME=roothide`.

## Build requirements

The camera processes on this A13 device use arm64e. Theos documents that current arm64e system-tweak ABI builds require Apple's linker, so build this project on macOS with Xcode, an iOS 16 SDK, and the RootHide Theos fork.

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/roothide/theos/master/bin/install-theos)"
export THEOS="$HOME/theos"
make clean package FINALPACKAGE=1
```

The resulting package is written to `packages/`. Install it through Sileo/Zebra on the RootHide jailbreak, then perform one userspace reboot or respring so SpringBoard and the camera services load the new tweak. The package scripts intentionally do not kill camera services during installation.

## Build without a Mac

The repository includes `.github/workflows/build-deb.yml`, which builds the RootHide package on a GitHub-hosted macOS runner.

1. Create an empty GitHub repository and upload the complete project, including the hidden `.github` directory.
2. Open the repository's **Actions** tab and select **Build RootHide DEB**.
3. Choose **Run workflow** and wait for the build to finish.
4. Open the completed run and download the **PrismCam-RootHide-DEB** artifact.
5. Extract the downloaded ZIP to obtain the `.deb` file.

The workflow is manual-only and does not need signing secrets. GitHub Actions packages artifacts as ZIP downloads, so the `.deb` is inside that ZIP.

## OBS on Windows

1. Install FFmpeg and ensure `ffmpeg.exe` is in `PATH`.
2. Open OBS and start **Virtual Camera**.
3. In PrismCam, select **OBS**, copy the pairing token, and enable the camera for four hours.
4. Find the iPhone's LAN IP and run:

```powershell
python tools\obs_relay.py --phone 192.168.1.50 --token TOKEN_FROM_APP
```

The relay captures `OBS Virtual Camera`, encodes 1280-wide MJPEG at 15 fps, and sends it to TCP port 5600. The phone listens only while OBS mode is armed. Pairing prevents accidental connections, but MJPEG is not encrypted; use a trusted LAN or an isolated hotspot.

## Validation

The validation script checks all property lists, Debian metadata, Python syntax, and accidental fixed `/var/jb` paths:

```sh
python3 scripts/validate_project.py
```

## Known limitation

`BWNodeOutput` and the two fallback classes are private camera-pipeline implementation details. The hook validates the method signature before installing, but Apple can change these classes between builds. This source targets iOS 16.2 and still requires on-device verification. If the app reports that no compatible hook was found, capture the class/selector diagnostics for that exact build instead of forcing an unchecked hook.

## References

- RootHide developer guide: https://github.com/roothide/Developer
- RootHide path model: https://github.com/roothide/Developer/blob/main/roothide.md
- Theos rootless/arm64e notes: https://theos.dev/docs/rootless

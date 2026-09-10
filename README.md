# android-cloud-phone

Run a full Android phone in your browser. Xvfb + Android Emulator + noVNC in one command.

```
 ./launch.sh
```

Opens at `http://<your-ip>:6080/vnc.html` — full Android 14 Pixel 7, touch input, keyboard, browser.

## Quick Start

```bash
git clone https://github.com/sj0404-collab/android-cloud-phone.git
cd android-cloud-phone
chmod +x install_deps.sh launch.sh
./install_deps.sh   # one-time setup (~2-3 min)
./launch.sh          # launch
```

## What's Inside

| Layer | Component |
|---|---|
| Display | Xvfb virtual framebuffer (1920x1080) |
| Android | Emulator — Pixel 7, Android 14, x86_64, KVM-accelerated |
| VNC | x11vnc (port 5900) + noVNC web client (port 6080) |

## Requirements

- Linux x86_64 with KVM support
- ~4 GB RAM, ~5 GB disk
- Internet (for first install)

## Ports

| Port | Service |
|---|---|
| 6080 | noVNC — open this in browser |
| 5900 | VNC — connect with any VNC client |
| 5554 | Emulator console |
| 5555 | ADB |

## ADB Access

```bash
adb connect localhost:5555
adb shell
adb install app.apk
```

## Docker

```bash
docker build -t android-cloud-phone .
docker run --privileged -p 6080:6080 -p 5900:5900 android-cloud-phone
```

## Troubleshooting

**No KVM** → emulator falls back to software (slow). Ensure `/dev/kvm` exists and user is in `kvm` group.

**Port already in use** → `launch.sh` auto-kills old instances. Or manually: `pkill -f Xvfb; pkill -f x11vnc; pkill -f websockify`.

**Black screen** → Android may still be booting. Wait up to 2 minutes.

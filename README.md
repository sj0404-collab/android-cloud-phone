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
| Display | Xvfb virtual framebuffer (resolves to device resolution, default 1080x2400) |
| Android | Emulator — Pixel 7, Android 14, x86_64, KVM-accelerated |
| VNC | x11vnc (port 5900) + noVNC web client (port 6080) |

## Android APK Launcher

Grab `CloudPhone-1.0.0-release.apk` from the latest GitHub Release — a signed Android wrapper with cover screen. It connects to the noVNC page of a running cloud-phone:

1. Set the server address (Settings → Сервер): `http://<host>:6080/vnc.html`
2. Tap **Запустить** — full-screen noVNC client, touch/keyboard support, black immersive UI.

Build yourself:

```bash
cd android
./gradlew :app:assembleRelease   # unsigned app-release-unsigned.apk
# sign with your own key:
zipalign -f -p 4 app/build/outputs/apk/release/app-release-unsigned.apk aligned.apk
apksigner sign --ks <your.keystore> --out CloudPhone-release.apk aligned.apk
```

The official release keystore is kept private and is NOT in this repository.

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

## GitHub Actions — Manual Runner Control

The repo ships with a workflow that runs the cloud phone on a **self-hosted runner** and gives you clickable **Run workflow** buttons on GitHub:

| Input | Effect |
|---|---|
| `start` | Boots the phone in background, shows the noVNC link in the run summary, renames the run to the URL, and (optionally) auto-opens the site in the runner browser |
| `stop` | Kills emulator / Xvfb / x11vnc / websockify |
| `status` | Reports if the phone is up and prints its URL |

Setup once:

1. Register this machine as a self-hosted runner (`runs-on: [self-hosted, linux, x64]`).
2. Add a GitHub token as a repo secret named **`GH_TOKEN`** (Settings → Secrets and variables → Actions), e.g. a fine-grained PAT with `actions: write` + `contents: read`. The built-in `GITHUB_TOKEN` is used as fallback.
3. In **Actions → Cloud Phone Runner → Run workflow**, pick the command. The URL is pinned to the run name and printed in the summary (auto-connect).

Local control (same commands, no GitHub):

```bash
bash scripts/control.sh start    # boot + print URL
bash scripts/control.sh status
bash scripts/control.sh stop
```

## Troubleshooting

**No KVM** → emulator falls back to software (slow). Ensure `/dev/kvm` exists and user is in `kvm` group.

**Port already in use** → `launch.sh` auto-kills old instances. Or manually: `pkill -f Xvfb; pkill -f x11vnc; pkill -f websockify`.

**Black screen** → Android may still be booting. Wait up to 2 minutes.

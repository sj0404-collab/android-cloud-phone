#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $*"; }
err() { echo -e "${RED}[x]${NC} $*"; exit 1; }

SDK_ROOT="${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}"
SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

log "Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
  xvfb x11vnc novnc websockify \
  curl wget unzip \
  mesa-utils libgl1-mesa-dri libgl1 \
  libegl1 libgles2 libglu1-mesa \
  libpulse0 libnss3 libatk-bridge2.0-0 \
  libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
  libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2 \
  2>/dev/null

# ── Android SDK ──────────────────────────────────────
if [ ! -d "$SDK_ROOT" ]; then
  log "Installing Android command-line tools..."
  mkdir -p "$SDK_ROOT/cmdline-tools"
  CDTOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  wget -q "$CDTOOLS_URL" -O /tmp/cmdline-tools.zip
  unzip -q -o /tmp/cmdline-tools.zip -d /tmp/cmdline-tools
  mv /tmp/cmdline-tools/cmdline-tools "$SDK_ROOT/cmdline-tools/latest"
  rm -rf /tmp/cmdline-tools /tmp/cmdline-tools.zip
fi

SDKMANAGER="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
chmod +x "$SDKMANAGER" 2>/dev/null || true

log "Installing Android SDK components..."
yes | "$SDKMANAGER" --licenses &>/dev/null || true
"$SDKMANAGER" \
  "platform-tools" \
  "emulator" \
  "platforms;android-34" \
  "system-images;android-34;default;x86_64" \
  2>&1 | grep -E "Installing|done|Error" || true

# ── KVM permissions ──────────────────────────────────
if [ -e /dev/kvm ]; then
  log "Setting up KVM access..."
  sudo groupadd -r kvm 2>/dev/null || true
  sudo gpasswd -a "$(whoami)" kvm 2>/dev/null || true
  log "KVM ready (group membership applies on next login)"
fi

log "Installation complete! Run ./launch.sh to start."

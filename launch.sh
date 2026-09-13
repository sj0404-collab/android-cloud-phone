#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*"; exit 1; }

SDK_ROOT="${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}"
EMULATOR="$SDK_ROOT/emulator/emulator"
ADB="$SDK_ROOT/platform-tools/adb"
AVD_NAME="phone"
DISPLAY_NUM=":99"
VNC_PORT=5900
NOVNC_PORT=6080
RESOLUTION="1080x2400"

banner() {
  echo -e "${CYAN}"
  cat << 'EOF'
    _             _     _ ____  _  ____
   / \   _ __ ___| |__ (_)/ ___|| |/ ___|
  / _ \ | '__/ __| '_ \| | |    | | |
 / ___ \| | | (__| | | | | |___ | |___
/_/   \_\_|  \___|_| |_|_|\____|_|\____|  ☁️  Cloud Phone
EOF
  echo -e "${NC}"
}

check_deps() {
  log "Checking dependencies..."
  local missing=()

  command -v Xvfb    >/dev/null || missing+=("xvfb")
  command -v x11vnc  >/dev/null || missing+=("x11vnc")
  command -v websockify >/dev/null || missing+=("novnc websockify")

  if [ ! -d "$SDK_ROOT/emulator" ]; then
    missing+=("android-sdk-emulator")
  fi
  if [ ! -d "$SDK_ROOT/system-images" ]; then
    missing+=("android-system-image")
  fi
  if [ ! -d "$SDK_ROOT/platform-tools" ]; then
    missing+=("android-platform-tools")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    warn "Missing packages: ${missing[*]}"
    if [ -f install_deps.sh ]; then
      log "Running install_deps.sh..."
      bash install_deps.sh
    else
      err "Run install_deps.sh first or install manually: ${missing[*]}"
    fi
  fi
  log "All dependencies OK"
}

stop_old() {
  log "Stopping old instances..."
  pkill -f "Xvfb $DISPLAY_NUM" 2>/dev/null || true
  pkill -f "x11vnc.*display.*$DISPLAY_NUM" 2>/dev/null || true
  pkill -f "websockify.*$NOVNC_PORT" 2>/dev/null || true
  pkill -f "emulator.*$AVD_NAME" 2>/dev/null || true
  sleep 1
}

start_xvfb() {
  local scr="${RESOLUTION%x*}x${RESOLUTION#*x}x24"
  log "Starting Xvfb on $DISPLAY_NUM ($RESOLUTION)..."
  Xvfb $DISPLAY_NUM -screen 0 "$scr" &>/dev/null &
  sleep 1
  export DISPLAY=$DISPLAY_NUM
  log "Xvfb started"
}

start_vnc() {
  log "Starting x11vnc on port $VNC_PORT..."
  # Perf flags for low-CPU headless runners: -nodri -noshm offload the copy,
  # -copyrect reuses unchanged screen regions, tight-ish quality keeps FPS up.
  x11vnc -display $DISPLAY_NUM -nopw -forever -shared -bg -rfbport $VNC_PORT \
    -noxdamage -nodri -noshm -copyrect -quality 6 -compresslevel 6 2>/dev/null
  log "x11vnc started"
}

start_novnc() {
  local novnc_path="/usr/share/novnc"
  if [ ! -f "$novnc_path/vnc.html" ]; then
    novnc_path="/usr/share/novnc"
    if [ ! -d "$novnc_path" ]; then
      warn "noVNC not found, trying to find it..."
      novnc_path=$(find / -name "vnc.html" -path "*/novnc/*" 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true)
      if [ -z "$novnc_path" ]; then
        err "noVNC not found. Install it or access via VNC client on port $VNC_PORT"
      fi
    fi
  fi
  log "Starting noVNC on port $NOVNC_PORT..."
  websockify --web "$novnc_path" $NOVNC_PORT localhost:$VNC_PORT &>/dev/null &
  sleep 1
  log "noVNC started"
}

create_avd() {
  local avd_dir="$HOME/.android/avd/$AVD_NAME.avd"
  local sysimg="$SDK_ROOT/system-images"
  local img_dir=""

  # Find x86_64 system image
  for candidate in \
    "$sysimg/android-34/default/x86_64" \
    "$sysimg/android-35/default/x86_64" \
    "$sysimg/android-33/default/x86_64"; do
    if [ -f "$candidate/system.img" ]; then
      img_dir="$candidate"
      break
    fi
  done

  if [ -z "$img_dir" ]; then
    err "No x86_64 system image found. Install one: sdkmanager 'system-images;android-34;default;x86_64'"
  fi

  if [ -f "$avd_dir/config.ini" ] && grep -q "^image.sysdir.1=$(realpath "$img_dir")/" "$avd_dir/config.ini" && [ -f "$avd_dir/system.img" ]; then
    log "AVD '$AVD_NAME' already exists"
    return
  fi

  log "Creating AVD '$AVD_NAME' from $img_dir..."
  mkdir -p "$avd_dir"

  cat > "$HOME/.android/avd/$AVD_NAME.ini" << INI
path=$avd_dir
path.rel=avd/$AVD_NAME.avd
target=$(echo "$img_dir" | grep -oP 'android-\d+')
INI

  cat > "$avd_dir/config.ini" << CFG
AvdId=$AVD_NAME
PlayStore.enabled=false
abi.type=x86_64
avd.ini.displayname=Cloud Phone
avd.ini.encoding=UTF-8
disk.dataPartition.size=2G
hw.cpu.arch=x86_64
hw.device.name=pixel_7
hw.device.manufacturer=Google
hw.lcd.density=420
hw.lcd.height=2400
hw.lcd.width=1080
hw.ramSize=4096
hw.keyboard=yes
hw.gpu.enabled=yes
hw.gpu.mode=host
image.sysdir.1=$(realpath "$img_dir")/
CFG

  for f in kernel-ranchu ramdisk.img system.img vendor.img userdata.img \
           encryptionkey.img advancedFeatures.ini build.prop source.properties; do
    [ -f "$img_dir/$f" ] && cp "$img_dir/$f" "$avd_dir/"
  done

  log "AVD created"
}

start_emulator() {
  log "Starting Android emulator ($RESOLUTION)..."
  export DISPLAY=$DISPLAY_NUM
  export ANDROID_SDK_ROOT="$SDK_ROOT"
  # Route emulator audio into the hub's cloud_phone Pulse sink so the panel
  # can hear the phone (pulse module-null-sink + loopback are created by hub).
  export PULSE_SINK="${CLOUD_PHONE_SINK:-cloud_phone}"
  export QEMU_AUDIO_DRV="${QEMU_AUDIO_DRV:-alsa}"
  # ALSA is forwarded to PulseAudio via ~/.asoundrc (type pulse), so phone
  # sound lands on the hub's cloud_phone sink; set QEMU_AUDIO_DRV=none to
  # disable sound entirely.

  # Render through Mesa (host GL / llvmpipe softpipe) instead of SwiftShader:
  # -gpu host on a GPU-less runner falls back to Mesa's llvmpipe, which keeps
  # more of Android's GLES/GL paths working than SwiftShader's GL2 wrapper.
  export LIBGL_ALWAYS_SOFTWARE=1
  export GALLIUM_DRIVER=llvmpipe
  export EGL_PLATFORM=x11

  # Never show the interactive crash/consent dialog on a headless runner.
  export ANDROID_EMU_DISABLE_CRASH_REPORTING=1
  export ANDROID_EMU_ENABLE_CRASH_REPORTING=0
  export CRASH_UPLOAD=no

  EXTRA_ARGS=""
  if [ ! -w /dev/kvm ] 2>/dev/null; then
    warn "No KVM access — emulator will be slow (software x86 → SwiftShader)"; 
  fi

  # Ensure KVM access
  if [ -w /dev/kvm ] 2>/dev/null; then
    :
  elif command -v sg >/dev/null; then
    sg kvm -c "$EMULATOR -avd $AVD_NAME \
      -gpu host -feature -Vulkan -no-boot-anim -no-snapshot -no-metrics \
      -crash-report-mode disabled \
      -port 5554 -skin $RESOLUTION" &>/dev/null &
    sleep 2
    return
  else
    warn "No KVM access, emulator may be slow"
  fi

  $EMULATOR -avd $AVD_NAME \
    -gpu host -feature -Vulkan -no-boot-anim -no-snapshot -no-metrics \
    -crash-report-mode disabled \
    -port 5554 -skin $RESOLUTION &>/dev/null &
  sleep 2
}

wait_for_boot() {
  log "Waiting for Android to boot (may take 1-2 min)..."
  $ADB wait-for-device 2>/dev/null

  for i in $(seq 1 60); do
    local boot
    boot=$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
    if [ "$boot" = "1" ]; then
      log "Android booted!"
      dismiss_anr
      return
    fi
    printf "\r  Booting... %d/60" "$i"
    sleep 2
  done
  warn "Boot timeout — Android may still be starting"
}

# Auto-dismiss ANR / SystemUI dialogs that block the screen after boot
# ("System UI isn't responding" → tap the "Close app" button on 1080x2400).
dismiss_anr() {
  log "Dismissing possible ANR/SystemUI dialogs..."
  for i in $(seq 1 5); do
    $ADB shell input tap 540 1273 2>/dev/null || true
    sleep 2
  done
  log "ANR check done"
}

open_browser() {
  log "Opening browser in emulator..."
  $ADB shell svc wifi enable 2>/dev/null || true
  sleep 2
  $ADB shell am start -a android.intent.action.VIEW \
    -d "https://www.google.com" &>/dev/null || true
}

get_ip() {
  local ip
  ip=$(curl -sf --max-time 5 ifconfig.me 2>/dev/null || \
       curl -sf --max-time 5 ipinfo.io/ip 2>/dev/null || \
       hostname -I | awk '{print $1}' || echo "localhost")
  echo "$ip"
}

print_summary() {
  local ip
  ip=$(get_ip)
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║           📱  Android Cloud Phone is READY          ║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  Browser:  ${GREEN}http://$ip:$NOVNC_PORT/vnc.html${NC}"
  echo -e "${CYAN}║${NC}  VNC:      ${GREEN}$ip:$VNC_PORT${NC}  (no password)"
  echo -e "${CYAN}║${NC}  ADB:      ${GREEN}$ip:5555${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  Device:   Pixel 7  •  Android 14  •  1080x2400"
  echo -e "${CYAN}║${NC}  Emulator: KVM-accelerated  •  x86_64"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
}

# ── Main ──────────────────────────────────────────────
banner
check_deps
stop_old
start_xvfb
create_avd
start_emulator
wait_for_boot
start_vnc
start_novnc
open_browser
print_summary

echo "Press Ctrl+C to shut down"
trap 'echo ""; log "Shutting down..."; pkill -f "emulator.*$AVD_NAME" 2>/dev/null; pkill -f x11vnc 2>/dev/null; pkill -f websockify 2>/dev/null; pkill -f "Xvfb $DISPLAY_NUM" 2>/dev/null; log "Done"; exit 0' INT TERM

wait

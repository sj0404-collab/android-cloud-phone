#!/usr/bin/env bash
set -euo pipefail

# Control script for the Cloud Phone runner (self-hosted GitHub runner).
# Usage: bash scripts/control.sh {start|stop|status}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIDFILE="$ROOT/.cloud-phone.pid"
LOGFILE="$ROOT/cloud-phone.log"
PORT_NOVNC=6080
DISPLAY_NUM=":99"

get_ip() {
  local ip
  ip=$(curl -sf --max-time 5 ifconfig.me 2>/dev/null || \
       curl -sf --max-time 5 ipinfo.io/ip 2>/dev/null || \
       hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
  echo "$ip"
}

site_url() {
  echo "http://$(get_ip):$PORT_NOVNC/vnc.html"
}

start() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
    echo "Cloud Phone already running (pid $(cat "$PIDFILE"))"
    status
    return 0
  fi

  cd "$ROOT"
  # Run the emulator in a transient systemd unit so it survives the GitHub
  # Actions job ending: the runner reaps every child of the job's cgroup, and
  # a plain `setsid nohup` still dies with it. systemd-run detaches us.
  if command -v systemd-run >/dev/null 2>&1; then
    systemd-run --collect --unit=cloud-phone --setenv=HOME="$HOME" \
      --working-directory="$ROOT" \
      bash "$ROOT/launch.sh" >> "$LOGFILE" 2>&1
    # systemd-run returns immediately; hand it a fresh pid marker.
    echo "Cloud Phone started via systemd (unit cloud-phone). Log: $LOGFILE"
  else
    setsid nohup bash launch.sh >> "$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"
    echo "Cloud Phone started (pid $(cat "$PIDFILE")). Log: $LOGFILE"
  fi

  for i in $(seq 1 60); do
    if curl -sf --max-time 2 "http://localhost:$PORT_NOVNC" >/dev/null 2>&1; then
      echo "noVNC is UP: $(site_url)"
      return 0
    fi
    sleep 2
  done
  echo "noVNC still booting, link (may lag a bit): $(site_url)"
}

stop() {
  systemctl stop cloud-phone 2>/dev/null || true
  pkill -f "qemu-system.*phone" 2>/dev/null || true
  pkill -f "websockify.*$PORT_NOVNC" 2>/dev/null || true
  pkill -f "x11vnc.*$DISPLAY_NUM" 2>/dev/null || true
  pkill -f "Xvfb $DISPLAY_NUM" 2>/dev/null || true
  systemctl reset-failed cloud-phone 2>/dev/null || true
  rm -f "$PIDFILE"
  echo "Cloud Phone stopped"
}

status() {
  if curl -sf --max-time 2 "http://localhost:$PORT_NOVNC" >/dev/null 2>&1; then
    echo "Cloud Phone: RUNNING at $(site_url)"
  else
    echo "Cloud Phone: STOPPED"
    [ -f "$PIDFILE" ] && echo "Stale pid file: $(cat "$PIDFILE")"
  fi
}

case "${1:-}" in
  start)  start ;;
  stop)   stop ;;
  status) status ;;
  *) echo "Usage: $0 {start|stop|status}"; exit 1 ;;
esac
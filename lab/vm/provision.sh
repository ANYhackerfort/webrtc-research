#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -s) == Linux ]] || exit 1
if ! command -v websockify >/dev/null || ! command -v x11vnc >/dev/null || ! command -v openbox >/dev/null; then
  sudo apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl python3 python3-websocket iproute2 iputils-ping ethtool tcpdump kmod xvfb x11vnc novnc websockify openbox dbus-x11
fi
if [[ ! -x /opt/google/chrome-canary/chrome ]]; then
  arch=$(dpkg --print-architecture)
  curl -fLsS --retry 2 "https://dl.google.com/linux/direct/google-chrome-canary_current_${arch}.deb" -o /tmp/scream-canary.deb
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y /tmp/scream-canary.deb
fi
if ! sudo modprobe sch_dualpi2; then
  sudo apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "linux-modules-extra-$(uname -r)"
  sudo modprobe sch_dualpi2
fi
/opt/google/chrome-canary/chrome --version
uname -r

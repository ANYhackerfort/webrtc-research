#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -s) == Linux ]] || { echo 'Run this inside Linux.' >&2; exit 1; }
[[ $EUID != 0 ]] || { echo 'Launch as your desktop user; this script invokes sudo.' >&2; exit 1; }
role=${1:-}
[[ $role == tx || $role == rx ]] || { echo "Usage: $0 tx|rx [absolute-video-path]" >&2; exit 2; }
lab_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
browser=${CHROME_BIN:-/opt/google/chrome-canary/chrome}
[[ -x $browser ]] || { echo "Canary executable missing: $browser" >&2; exit 1; }
video=${2:-"$lab_dir/../media/news_cif.y4m"}
if [[ $role == tx ]]; then
  [[ -r $video ]] || { echo "Video missing: $video" >&2; exit 1; }
  video=$(realpath -- "$video")
fi
mkdir -p "$lab_dir/../runs"
run_dir=$(mktemp -d "$lab_dir/../runs/${role}-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
flags=(
  "--user-data-dir=$lab_dir/../profiles/$role"
  --no-first-run --no-default-browser-check
  --disable-background-networking
  --disable-features=WebRtcHideLocalIpsWithMdns
  --force-fieldtrials=WebRTC-RFC8888CongestionControlFeedback/Enabled,offer:true/WebRTC-Bwe-ScreamV2/Enabled/
  --enable-logging=stderr
  --vmodule=scream_network_controller=2,scream_v2=2,goog_cc_factory=2
  --disable-background-timer-throttling
  --disable-backgrounding-occluded-windows
  --disable-renderer-backgrounding
)
if [[ $role == tx ]]; then
  flags+=(--use-fake-device-for-media-stream --use-fake-ui-for-media-stream
    "--use-file-for-fake-video-capture=$video")
fi
{
  date -u
  "$browser" --version
  uname -a
  tc -V
  printf '%q ' "$browser" "${flags[@]}" "http://localhost:8000/?role=$role"
  printf '\n'
  [[ $role != tx ]] || sha256sum "$video"
} > "$run_dir/environment.txt"
echo "Logs: $run_dir"
echo 'Close the previous lab browser for this role before relaunching.'
sudo -v
# Run both children under the desktop user's shell so it can clean up its server.
sudo ip netns exec "scream-$role" sudo -u "$(id -un)" env \
  "DISPLAY=${DISPLAY:-}" "XAUTHORITY=${XAUTHORITY:-}" \
  "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}" "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}" \
  "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-}" \
  bash -c '
    set -euo pipefail
    lab_dir=$1
    run_dir=$2
    shift 2
    python3 -m http.server 8000 --bind 127.0.0.1 --directory "$lab_dir" \
      > "$run_dir/http.log" 2>&1 &
    server_pid=$!
    trap '\''kill "$server_pid" 2>/dev/null || true'\'' EXIT
    sleep 1
    kill -0 "$server_pid" 2>/dev/null || {
      echo "HTTP server failed; inspect $run_dir/http.log" >&2
      exit 1
    }
    "$@" > "$run_dir/browser.stdout.log" 2> "$run_dir/browser.stderr.log"
  ' bash "$lab_dir" "$run_dir" "$browser" "${flags[@]}" "http://localhost:8000/?role=$role"

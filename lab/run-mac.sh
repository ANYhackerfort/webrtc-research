#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -s) == Darwin ]] || { echo 'Use this launcher on macOS.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Install Python 3, then run this command again.' >&2; exit 1; }
lab_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd -- "$lab_dir/.." && pwd)
browser=${CHROME_BIN:-'/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary'}
if [[ ! -x $browser && -z ${CHROME_BIN:-} ]]; then
  browser="$HOME/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"
fi
[[ -x $browser ]] || { echo 'Install Canary first: bash lab/install-canary-mac.sh' >&2; exit 1; }
mkdir -p "$root_dir/media" "$root_dir/runs"
video="$root_dir/media/news_cif.y4m"
if [[ ! -s $video ]]; then
  echo 'Downloading the news clip (about 46 MB)…'
  curl -fL --retry 2 https://media.xiph.org/video/derf/y4m/news_cif.y4m -o "$video.part"
  mv "$video.part" "$video"
fi
run_dir=$(mktemp -d "$root_dir/runs/mac-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
session=$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')
server_pid=''
tx_pid=''
rx_pid=''
cleanup() {
  trap - EXIT INT TERM
  for pid in "$tx_pid" "$rx_pid" "$server_pid"; do
    [[ -z $pid ]] || kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
python3 "$lab_dir/demo-server.py" --session "$session" --ready "$run_dir/url.txt" \
  > "$run_dir/http.log" 2>&1 &
server_pid=$!
for attempt in {1..50}; do
  [[ ! -s $run_dir/url.txt ]] || break
  kill -0 "$server_pid" 2>/dev/null || { cat "$run_dir/http.log" >&2; exit 1; }
  sleep 0.1
done
[[ -s $run_dir/url.txt ]] || { echo 'Page server did not start.' >&2; exit 1; }
base_url=$(cat "$run_dir/url.txt")
flags=(
  --no-first-run --no-default-browser-check --new-window
  --disable-background-networking
  --disable-features=WebRtcHideLocalIpsWithMdns
  --force-fieldtrials=WebRTC-RFC8888CongestionControlFeedback/Enabled,offer:true/WebRTC-Bwe-ScreamV2/Enabled/
  --enable-logging=stderr
  --vmodule=scream_network_controller=2,scream_v2=2,goog_cc_factory=2
  --autoplay-policy=no-user-gesture-required
  --disable-background-timer-throttling
  --disable-backgrounding-occluded-windows
  --disable-renderer-backgrounding
  --window-size=700,920
)
{
  date -u
  "$browser" --version
  uname -a
  shasum -a 256 "$video"
  printf '%q ' "$browser" "${flags[@]}"
  printf '\nDirect Mac connection; no emulated bottleneck.\n'
} > "$run_dir/environment.txt"
echo 'Opening SENDER and RECEIVER windows. In SENDER, click Start video.'
echo 'The description exchange is automatic. Keep this terminal open; Ctrl+C stops the demo.'
echo 'Mode: direct connection on this Mac, without a DualPI2 bottleneck.'
echo "Browser: $browser"
echo "Logs: $run_dir"
"$browser" "${flags[@]}" "--user-data-dir=$run_dir/profile-tx" \
  --window-position=0,30 --use-fake-device-for-media-stream --use-fake-ui-for-media-stream \
  "--use-file-for-fake-video-capture=$video" \
  "$base_url/?role=tx&auto=1&mode=mac&session=$session" \
  > "$run_dir/tx.stdout.log" 2> "$run_dir/tx.stderr.log" &
tx_pid=$!
"$browser" "${flags[@]}" "--user-data-dir=$run_dir/profile-rx" --window-position=710,30 \
  "$base_url/?role=rx&auto=1&mode=mac&session=$session" \
  > "$run_dir/rx.stdout.log" 2> "$run_dir/rx.stderr.log" &
rx_pid=$!
while kill -0 "$tx_pid" 2>/dev/null && kill -0 "$rx_pid" 2>/dev/null; do sleep 1; done

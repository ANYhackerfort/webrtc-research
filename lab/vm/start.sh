#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -s) == Linux && $EUID != 0 ]] || { echo 'Run as the regular Linux VM user.' >&2; exit 1; }
vm_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
lab_dir=$(cd -- "$vm_dir/.." && pwd)
root_dir=$(cd -- "$lab_dir/.." && pwd)
browser=/opt/google/chrome-canary/chrome
mkdir -p "$root_dir/runs"
run_dir=$(mktemp -d "$root_dir/runs/vm-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
profiles=$(mktemp -d /tmp/scream-vm-profiles-XXXXXX)
session=$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')
mkdir "$run_dir/shared"
python3 - "$root_dir/runs/vm-current.json" "$run_dir" "$session" "$$" <<'PY'
import json,sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({'run_dir':sys.argv[2],'session':sys.argv[3],'pid':int(sys.argv[4])}))
PY
pids=()
cleanup() {
  trap - EXIT INT TERM
  for pid in "${pids[@]}"; do sudo kill "$pid" 2>/dev/null || true; done
  sudo bash "$lab_dir/topology.sh" down || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sudo bash "$lab_dir/topology.sh" up > "$run_dir/topology-start.log" 2>&1
{
  "$browser" --version
  uname -a
  tc -V
  sha256sum "$root_dir/media/news_cif.y4m"
} > "$run_dir/environment.txt"
Xvfb :99 -screen 0 1600x1100x24 -ac -nolisten tcp > "$run_dir/xvfb.log" 2>&1 &
pids+=("$!")
export DISPLAY=:99
sleep 1
openbox > "$run_dir/openbox.log" 2>&1 &
pids+=("$!")
x11vnc -display :99 -localhost -nopw -forever -shared -quiet > "$run_dir/vnc.log" 2>&1 &
pids+=("$!")
websockify --web=/usr/share/novnc 127.0.0.1:6080 127.0.0.1:5900 > "$run_dir/novnc.log" 2>&1 &
pids+=("$!")
flags=(--no-first-run --no-default-browser-check --new-window --ozone-platform=x11
  --disable-gpu --disable-dev-shm-usage --disable-background-networking
  --disable-features=WebRtcHideLocalIpsWithMdns
  --force-fieldtrials=WebRTC-RFC8888CongestionControlFeedback/Enabled,offer:true/WebRTC-Bwe-ScreamV2/Enabled/
  --enable-logging=stderr --vmodule=scream_network_controller=2,scream_v2=2,goog_cc_factory=2
  --autoplay-policy=no-user-gesture-required --disable-background-timer-throttling
  --disable-backgrounding-occluded-windows --disable-renderer-backgrounding
  --remote-debugging-port=9222 --remote-allow-origins=http://localhost:9222 --window-size=790,1050)
for role in tx rx; do
  sudo ip netns exec "scream-$role" sudo -u "$(id -un)" \
    python3 "$lab_dir/demo-server.py" --port 8000 --session "$session" \
    --ready "$run_dir/$role-url.txt" --shared-dir "$run_dir/shared" --record-path "$run_dir/$role-metrics.jsonl" \
    > "$run_dir/$role-http.log" 2>&1 &
  pids+=("$!")
done
sleep 1
sudo ip netns exec scream-tx sudo -u "$(id -un)" env DISPLAY=:99 \
  "$browser" "${flags[@]}" "--user-data-dir=$profiles/tx" --window-position=0,0 \
  --use-fake-device-for-media-stream --use-fake-ui-for-media-stream \
  "--use-file-for-fake-video-capture=$root_dir/media/news_cif.y4m" \
  "http://localhost:8000/?role=tx&auto=1&mode=vm&record=1&session=$session" \
  > "$run_dir/tx.stdout.log" 2> "$run_dir/tx.stderr.log" &
pids+=("$!")
sudo ip netns exec scream-rx sudo -u "$(id -un)" env DISPLAY=:99 \
  "$browser" "${flags[@]}" "--user-data-dir=$profiles/rx" --window-position=800,0 \
  "http://localhost:8000/?role=rx&auto=1&mode=vm&record=1&session=$session" \
  > "$run_dir/rx.stdout.log" 2> "$run_dir/rx.stderr.log" &
pids+=("$!")
python3 "$vm_dir/control.py" --run-dir "$run_dir" --project "$root_dir" --session "$session" \
  > "$run_dir/control.log" 2>&1 &
pids+=("$!")
sleep 5
sudo ip netns exec scream-tx python3 "$vm_dir/drive.py" "document.getElementById('offer').click(); 'started'" \
  > "$run_dir/auto-start.log" 2>&1
echo "Linux bottleneck demo ready: $run_dir"
wait

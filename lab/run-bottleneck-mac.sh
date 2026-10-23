#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -s) == Darwin ]] || { echo 'Use this launcher on macOS.' >&2; exit 1; }
lab_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd -- "$lab_dir/.." && pwd)
command -v limactl >/dev/null || { echo 'Installing Lima for the dedicated Linux VM…'; HOMEBREW_NO_AUTO_UPDATE=1 brew install lima; }
if [[ ${1:-} == stop ]]; then
  limactl shell scream-l4s -- python3 "$lab_dir/vm/daemon.py" stop "$root_dir" || true
  limactl stop scream-l4s
  exit 0
fi
[[ $(uname -m) == arm64 ]] || { echo 'This VM launcher currently targets Apple Silicon.' >&2; exit 1; }
mkdir -p "$root_dir/runs" "$root_dir/media"
if [[ ! -s $root_dir/media/news_cif.y4m ]]; then
  curl -fL --retry 2 https://media.xiph.org/video/derf/y4m/news_cif.y4m -o "$root_dir/media/news_cif.y4m"
fi
if limactl list --json | python3 -c 'import json,sys; sys.exit(0 if any(json.loads(line).get("name")=="scream-l4s" for line in sys.stdin if line.strip()) else 1)'; then
  limactl start --tty=false scream-l4s
else
  python3 - "$root_dir" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1])
config={'vmType':'vz','arch':'aarch64',
 'images':[{'location':'https://cloud-images.ubuntu.com/resolute/20261016/resolute-server-cloudimg-arm64.img',
            'arch':'aarch64','digest':'sha256:8eb876c2ccc4b6ff89e4a65d511815923b285e04503ba465809bf587f763da24'}],
 'cpus':4,'memory':'4GiB','disk':'20GiB','mountType':'virtiofs',
 'mounts':[{'location':str(root),'writable':True}],
 'containerd':{'system':False,'user':False},
 'portForwards':[{'guestPort':6080,'hostPort':16080},{'guestPort':8080,'hostPort':18080}]}
(root/'runs/scream-l4s.yaml').write_text(json.dumps(config,indent=2))
PY
  limactl start --name=scream-l4s --tty=false "$root_dir/runs/scream-l4s.yaml"
fi
limactl shell scream-l4s -- bash "$lab_dir/vm/provision.sh"
limactl shell scream-l4s -- python3 "$lab_dir/vm/daemon.py" start "$root_dir"
echo 'Waiting for the bottleneck control panel…'
for attempt in {1..60}; do
  if curl -fsS http://127.0.0.1:18080/api/state >/dev/null 2>&1; then
    echo 'Open http://127.0.0.1:18080/ to see the Linux Canary browsers and queue controls.'
    echo 'The video starts automatically. Choose Compare FIFO vs DualPI2 to measure both queues.'
    echo 'Stop the VM with: bash lab/run-bottleneck-mac.sh stop'
    open http://127.0.0.1:18080/
    exit 0
  fi
  sleep 1
done
echo 'Startup did not finish. Inspect runs/vm-launcher.log and the latest runs/vm-... logs.' >&2
exit 1

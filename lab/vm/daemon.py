#!/usr/bin/env python3
"""Start or stop only this project's VM demonstration process."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

action, root = sys.argv[1], Path(sys.argv[2])
current = root / 'runs/vm-current.json'
if current.exists():
    data = json.loads(current.read_text())
    pid = data.get('pid')
    proc = Path(f'/proc/{pid}/cmdline')
    alive = proc.exists() and str(root / 'lab/vm/start.sh').encode() in proc.read_bytes()
    if alive and action == 'start':
        print('The bottleneck demo is already running.')
        sys.exit(0)
    if alive and action == 'stop':
        os.kill(pid, signal.SIGTERM)
        print('Stopped the bottleneck demo.')
        sys.exit(0)
if action == 'start':
    (root / 'runs').mkdir(exist_ok=True)
    with (root / 'runs/vm-launcher.log').open('a') as log:
        process = subprocess.Popen(['bash', str(root / 'lab/vm/start.sh')], cwd=root,
                                   stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
    print(f'Starting the bottleneck demo (PID {process.pid}).')

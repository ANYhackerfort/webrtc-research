#!/usr/bin/env python3
"""Local controls and telemetry for the dedicated SCReAM Linux VM."""
import argparse
import http.server
import json
from pathlib import Path
import subprocess
import threading
import time
from urllib.parse import urlsplit


def read_json(path, default=None):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def last_metric(path):
    try:
        lines = path.read_text().splitlines()
        return json.loads(lines[-1]) if lines else None
    except (OSError, ValueError):
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run-dir', type=Path, required=True)
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--session', required=True)
    args = parser.parse_args()
    topology = args.project / 'lab/topology.sh'
    comparison = None

    def command(*parts):
        return subprocess.check_output(parts, text=True, stderr=subprocess.STDOUT)

    def queue_state():
        return json.loads(command('sudo', 'ip', 'netns', 'exec', 'scream-router', 'tc', '-j', '-s', 'qdisc', 'show', 'dev', 'rr0'))

    def state():
        return {'queue': queue_state(),
                'tx': last_metric(args.run_dir / 'tx-metrics.jsonl'),
                'rx': last_metric(args.run_dir / 'rx-metrics.jsonl'),
                'progress': read_json(args.run_dir / 'comparison-progress.json'),
                'comparison': read_json(args.run_dir / 'comparison.json'),
                'comparing': comparison is not None and comparison.poll() is None,
                'run_dir': str(args.run_dir)}

    def record_queue():
        while True:
            try:
                with (args.run_dir / 'queue-metrics.jsonl').open('a') as output:
                    output.write(json.dumps({'at': time.time(), 'queue': queue_state()}) + '\n')
            except (OSError, ValueError, subprocess.CalledProcessError):
                pass
            time.sleep(1)

    class Handler(http.server.BaseHTTPRequestHandler):
        def json_response(self, value):
            body = json.dumps(value).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if urlsplit(self.path).path == '/api/state':
                return self.json_response(state())
            if urlsplit(self.path).path != '/':
                return self.send_error(404)
            body = (Path(__file__).parent / 'control.html').read_text().replace('__SESSION__', args.session).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            nonlocal comparison
            if self.headers.get('X-Lab-Token') != args.session:
                return self.send_error(403)
            if urlsplit(self.path).path != '/api/control':
                return self.send_error(404)
            try:
                length = int(self.headers.get('Content-Length', 0))
                if not 0 < length < 1000:
                    raise ValueError('Invalid request size')
                action = json.loads(self.rfile.read(length))['action']
                if comparison is not None and comparison.poll() is None:
                    return self.send_error(409, 'Comparison is running; wait for it to finish.')
                if action in ('250kbit', '1mbit'):
                    output = command('sudo', 'bash', str(topology), 'rate', action)
                elif action in ('dualpi2', 'fifo'):
                    output = command('sudo', 'bash', str(topology), 'queue', action)
                elif action == 'compare':
                    log = (args.run_dir / 'comparison.log').open('a')
                    comparison = subprocess.Popen(['python3', str(Path(__file__).parent / 'compare.py'),
                        '--run-dir', str(args.run_dir), '--project', str(args.project), '--session', args.session],
                        stdout=log, stderr=subprocess.STDOUT)
                    log.close()
                    output = 'Comparison started: FIFO, then DualPI2, with fresh calls and equal capacity.'
                else:
                    raise ValueError('Unknown action')
                self.json_response({'ok': True, 'message': output})
            except (ValueError, KeyError, subprocess.CalledProcessError) as error:
                self.json_response({'ok': False, 'message': str(error)})

    threading.Thread(target=record_queue, daemon=True).start()
    http.server.ThreadingHTTPServer(('127.0.0.1', 8080), Handler).serve_forever()


if __name__ == '__main__':
    main()

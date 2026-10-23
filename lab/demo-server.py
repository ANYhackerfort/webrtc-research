#!/usr/bin/env python3
"""Loopback-only page server and in-memory SDP relay for the Mac demo."""
import argparse
import functools
import http.server
import json
import os
from pathlib import Path
import tempfile
import threading
from urllib.parse import parse_qs, urlsplit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', required=True)
    parser.add_argument('--ready', required=True, type=Path)
    parser.add_argument('--port', type=int, default=0)
    parser.add_argument('--shared-dir', type=Path)
    parser.add_argument('--record-path', type=Path)
    args = parser.parse_args()
    descriptions = {}
    lock = threading.Lock()
    if args.shared_dir:
        args.shared_dir.mkdir(parents=True, exist_ok=True)

    class Handler(http.server.SimpleHTTPRequestHandler):
        def signal_kind(self):
            query = parse_qs(urlsplit(self.path).query)
            kind = query.get('kind', [''])[0]
            if query.get('session', [''])[0] != args.session or kind not in ('offer', 'answer'):
                self.send_error(403)
                return None
            return kind

        def respond_json(self, value):
            body = json.dumps(value).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if urlsplit(self.path).path != '/signal':
                return super().do_GET()
            kind = self.signal_kind()
            if kind:
                with lock:
                    path = args.shared_dir / f'{kind}.json' if args.shared_dir else None
                    value = json.loads(path.read_text()) if path and path.exists() else descriptions.get(kind)
                self.respond_json(value)

        def do_POST(self):
            endpoint = urlsplit(self.path).path
            if endpoint not in ('/signal', '/record'):
                return self.send_error(404)
            allowed = {f'http://localhost:{self.server.server_port}',
                       f'http://127.0.0.1:{self.server.server_port}'}
            if self.headers.get('Origin') not in allowed:
                return self.send_error(403)
            kind = self.signal_kind() if endpoint == '/signal' else None
            if endpoint == '/signal' and not kind:
                return
            if endpoint == '/record':
                query = parse_qs(urlsplit(self.path).query)
                if not args.record_path or query.get('session', [''])[0] != args.session:
                    return self.send_error(403)
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length < 2_000_000:
                    raise ValueError('Invalid body length')
                value = json.loads(self.rfile.read(length))
                if not isinstance(value, dict):
                    raise ValueError('Expected an object')
                if endpoint == '/signal' and (value.get('type') != kind or not isinstance(value.get('sdp'), str)):
                    raise ValueError('Invalid session description')
                if endpoint == '/record' and not isinstance(value.get('summary'), list):
                    raise ValueError('Expected measured statistics')
            except (ValueError, TypeError):
                return self.send_error(400)
            with lock:
                if endpoint == '/record':
                    with args.record_path.open('a') as output:
                        output.write(json.dumps(value) + '\n')
                elif args.shared_dir:
                    with tempfile.NamedTemporaryFile(mode='w', dir=args.shared_dir, delete=False) as output:
                        json.dump(value, output)
                        temp_path = output.name
                    os.replace(temp_path, args.shared_dir / f'{kind}.json')
                else:
                    descriptions[kind] = value
            self.respond_json({'ok': True})

    handler = functools.partial(Handler, directory=str(Path(__file__).resolve().parent))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', args.port), handler)
    args.ready.write_text(f'http://localhost:{server.server_port}')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Control a lab browser from within its own network namespace."""
import argparse
import json
import time
import urllib.request
import websocket


def evaluate(expression):
    with urllib.request.urlopen('http://localhost:9222/json/list', timeout=5) as response:
        targets = json.load(response)
    target = next(t for t in targets if t.get('type') == 'page' and t.get('url') != 'chrome://newtab/')
    connection = websocket.create_connection(target['webSocketDebuggerUrl'], origin='http://localhost:9222', timeout=10)
    try:
        connection.send(json.dumps({'id': 1, 'method': 'Runtime.evaluate', 'params': {
            'expression': expression, 'returnByValue': True, 'awaitPromise': True}}))
        while True:
            result = json.loads(connection.recv())
            if result.get('id') == 1:
                if result.get('result', {}).get('exceptionDetails'):
                    raise RuntimeError(result['result']['exceptionDetails'])
                return result.get('result', {}).get('result', {}).get('value')
    finally:
        connection.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('expression')
    args = parser.parse_args()
    for attempt in range(40):
        try:
            print(json.dumps(evaluate(args.expression)))
            break
        except (OSError, StopIteration):
            if attempt == 39:
                raise
            time.sleep(.5)

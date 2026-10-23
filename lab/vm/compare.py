#!/usr/bin/env python3
"""Compare fresh SCReAM calls through FIFO and DualPI2 at equal capacity."""
import argparse
import json
from pathlib import Path
import shutil
import signal
import statistics
import subprocess
import time
from urllib.parse import urlencode


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run-dir', required=True, type=Path)
    parser.add_argument('--project', required=True, type=Path)
    parser.add_argument('--session', required=True)
    parser.add_argument('--duration', type=int, default=30)
    args = parser.parse_args()
    drive = args.project / 'lab/vm/drive.py'
    topology = args.project / 'lab/topology.sh'

    def progress(message):
        (args.run_dir / 'comparison-progress.json').write_text(json.dumps({'message': message, 'at': time.time()}))
        print(message, flush=True)

    def run(*cmd):
        return subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT)

    def browser(role, expression):
        return run('sudo', 'ip', 'netns', 'exec', f'scream-{role}', 'python3', str(drive), expression)

    def read_metrics(role):
        path = args.run_dir / f'{role}-metrics.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def summarize(mode, log_start):
        tx = read_metrics('tx')
        rx = read_metrics('rx')
        rtts = [s['rttMs'] for row in tx[5:] for s in row['summary'] if s.get('selectedPair') and isinstance(s.get('rttMs'), (float, int))]
        bitrates = [s['kbps'] for row in rx[5:] for s in row['summary'] if s.get('direction') == 'inbound-rtp' and isinstance(s.get('kbps'), (float, int))]
        videos = [s for row in rx for s in row['summary'] if s.get('direction') == 'inbound-rtp']
        last = videos[-1] if videos else {}
        sender_log = (args.run_dir / 'tx.stderr.log').read_text(errors='replace')[log_start:]
        rtts.sort()
        def packets(where, mark):
            path = args.run_dir / f'{mode}-{where}.pcap'
            output = run('sudo', 'tcpdump', '-nr', str(path), f'udp and (ip[1] & 3) = {mark}')
            return sum(line[:1].isdigit() for line in output.splitlines())
        result = {
            'medianRttMs': statistics.median(rtts) if rtts else None,
            'p95RttMs': rtts[min(len(rtts)-1, int(.95*len(rtts)))] if rtts else None,
            'medianRxKbps': statistics.median(bitrates) if bitrates else None,
            'ceReceived': last.get('packetsReceivedWithCe'),
            'ect1Received': last.get('packetsReceivedWithEct1'),
            'framesDecoded': last.get('framesDecoded'),
            'screamExecuted': 'ScreamV2:' in sender_log,
            'screamSawCe': 'is_ce=1' in sender_log,
            'ingressEct1Packets': packets('ingress', 1),
            'receiverCePackets': packets('receiver', 3),
            'sampleCount': len(rx),
            'capacity': '1mbit', 'warmupSamplesExcluded': 5,
            'selectedPaths': [s for s in tx[-1]['summary'] if s.get('selectedPair')] if tx else [],
        }
        for role in ('tx', 'rx'):
            shutil.copyfile(args.run_dir / f'{role}-metrics.jsonl', args.run_dir / f'{mode}-{role}-metrics.jsonl')
        (args.run_dir / f'{mode}-sender.log').write_text(sender_log)
        (args.run_dir / f'{mode}-queue.json').write_text(run('sudo', 'ip', 'netns', 'exec', 'scream-router', 'tc', '-j', '-s', 'qdisc', 'show', 'dev', 'rr0'))
        return result

    results = {}
    try:
        for mode in ('fifo', 'dualpi2'):
            progress(f'Starting a fresh call through {mode}, at 1 Mbit/s…')
            for role in ('tx', 'rx'):
                browser(role, "location.href='about:blank'; 'reset'")
            time.sleep(1)
            for path in (args.run_dir / 'shared').glob('*.json'):
                path.unlink()
            for role in ('tx', 'rx'):
                (args.run_dir / f'{role}-metrics.jsonl').write_text('')
            run('sudo', 'bash', str(topology), 'rate', '1mbit')
            run('sudo', 'bash', str(topology), 'queue', mode)
            log_start = len((args.run_dir / 'tx.stderr.log').read_text(errors='replace'))
            captures = []
            for where, namespace, interface in [('ingress', 'scream-router', 'rt0'), ('receiver', 'scream-rx', 'rx0')]:
                captures.append(subprocess.Popen(['sudo', 'ip', 'netns', 'exec', namespace, 'tcpdump', '-U', '-n', '-i', interface,
                    '-s', '0', '-w', str(args.run_dir / f'{mode}-{where}.pcap'),
                    'udp and src host 10.200.1.2 and dst host 10.200.2.2'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            try:
                for role in ('rx', 'tx'):
                    url = 'http://localhost:8000/?' + urlencode({'role':role,'auto':'1','mode':'vm','record':'1','session':args.session})
                    browser(role, f'location.href={json.dumps(url)}; "loading"')
                time.sleep(2)
                browser('tx', "document.getElementById('offer').click(); 'started'")
                for _ in range(30):
                    if read_metrics('rx'):
                        break
                    time.sleep(1)
                else:
                    raise RuntimeError('Receiver did not begin recording video statistics.')
                for elapsed in range(args.duration):
                    progress(f'{mode}: recording {elapsed + 1}/{args.duration} seconds at 1 Mbit/s')
                    time.sleep(1)
            finally:
                for process in captures:
                    subprocess.run(['sudo', 'kill', '-INT', str(process.pid)], check=False)
                for process in captures:
                    process.wait(timeout=10)
            results[mode] = summarize(mode, log_start)
        results['notes'] = 'One VP9/CIF flow; same SCReAM flags and capacity; fresh call for each queue; not a general L4S benchmark.'
        (args.run_dir / 'comparison.json').write_text(json.dumps(results, indent=2))
        progress('Comparison complete. DualPI2 remains active; the video continues playing.')
    except Exception as error:
        progress(f'Comparison failed: {error}')
        raise


if __name__ == '__main__':
    main()

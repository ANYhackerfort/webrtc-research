# SCReAM WebRTC research lab

Send VP9 video between two Chrome Canary browsers using the browser's native SCReAMv2 congestion controller. Inspect bitrate, RTT, packet-arrival feedback, and ECN counters, or compare FIFO and DualPI2 queues in a Linux VM.

## Quick start

Clone this repository and open its directory before running the commands below. You need Python 3; the VM setup also needs Homebrew on an Apple Silicon Mac.

### Native Mac preview

```bash
bash lab/install-canary-mac.sh
bash lab/run-mac.sh
```

Click **Start video** in the sender window. The receiver connects automatically. Press **Ctrl+C** in the terminal to stop.

This preview uses a direct Mac connection with no controlled bottleneck. See [Mac quick start](MAC-QUICKSTART.md).

### Linux bottleneck on an Apple Silicon Mac

```bash
bash lab/run-bottleneck-mac.sh
```

The launcher installs Lima if needed, provisions a Linux VM, and opens the control panel at <http://127.0.0.1:18080/>. The VM uses 4 CPUs, 4 GiB RAM, and a 20 GiB virtual disk. Both Canary browsers and the router queue run inside the VM.

Use the controls to change capacity, choose FIFO or DualPI2, and compare fresh calls at equal capacity. Results and packet captures are saved locally under `runs/`.

```bash
bash lab/run-bottleneck-mac.sh stop
```

See [bottleneck quick start](BOTTLENECK-QUICKSTART.md) or the [full setup guide](SCREAM-CANARY-GUIDE.md), which also covers manual Linux setup.

## How SCReAM connects to WebRTC

The launchers enable two native WebRTC field trials in both Canary processes:

```text
--force-fieldtrials=WebRTC-RFC8888CongestionControlFeedback/Enabled,offer:true/WebRTC-Bwe-ScreamV2/Enabled/
```

`lab/app.js` creates a regular `RTCPeerConnection`, adds a VP9 video track with a 2 Mbps ceiling, and requires `ack ccfb` in the offer and answer. The receiver returns RFC 8888 packet-arrival and ECN feedback. SCReAM runs inside Canary's native WebRTC stack and controls the sender's rate.

```text
Video → Canary sender → network / optional queue → Canary receiver
              ↑                                         │
        SCReAM rate control ←────── RTCP feedback ─────────┘
```

The JavaScript sets up the call and collects statistics. SCReAM's control loop is implemented in the browser. Sender logs contain `ScreamV2:` reports with `target_rate`, congestion-window updates, and CE observations. ECT(1) or CE counters alone do not establish that the controller is running.

See the upstream [SCReAMv2 WebRTC documentation](https://webrtc.googlesource.com/src/+/main/modules/congestion_controller/scream/g3doc/index.md).

## Project layout

- `lab/app.js`, `lab/index.html`, `lab/charts.js`: call setup and live statistics.
- `lab/demo-server.py`: local page server and signaling.
- `lab/run-mac.sh`, `lab/install-canary-mac.sh`: native Mac preview.
- `lab/run-bottleneck-mac.sh`, `lab/vm/`: Linux VM, browser display, controls, and comparison runner.
- `lab/topology.sh`, `lab/launch.sh`: manual Linux namespace topology and browser launcher.

The launchers download the [Xiph news test clip](https://media.xiph.org/video/derf/y4m/news_cif.y4m) when needed. Downloaded media, browser profiles, run logs, captures, and generated document/archive copies are excluded from Git.

# Run the video through a bottleneck on your Mac

In Terminal:

```bash
cd ~/Desktop/webrtc-research
bash lab/run-bottleneck-mac.sh
```

Open **http://127.0.0.1:18080/** if the control panel does not open automatically. The video starts automatically.

```text
             One Linux VM running on your Mac

Canary sender → [rate limit + DualPI2 queue] → Canary receiver
              ←────── RTCP feedback ────────
```

The two browsers displayed inside the page run in Linux. The Mac browser is the viewer. Video packets stay inside the VM and must cross the router queue.

Use the controls above the browser view:

- **DualPI2 / ECN:** the congestion-marking queue.
- **FIFO baseline / no marking:** a queue without ECN marking.
- **250 kbit/s / 1 Mbit/s:** change the bottleneck capacity.
- **Compare FIFO vs DualPI2:** run a fresh 30-second video call through each queue at the same 1 Mbit/s capacity. The result table shows measured RTT, received bitrate, and CE counts. DualPI2 remains active afterward.

Look for increasing **CE packets received** in the receiver. The control panel shows the active queue and the selected packet path; results and packet captures are saved under `runs/vm-...`.

To stop the demo and its VM:

```bash
bash lab/run-bottleneck-mac.sh stop
```

The first setup installs Lima and creates an Ubuntu VM with 4 CPUs, 4 GiB RAM, and a 20 GiB virtual disk. Later starts reuse it. This launcher currently supports Apple Silicon Macs. The project's folder is shared with that VM for code, video, and results.

This Mac's Docker Desktop kernel lacks DualPI2, so this setup uses a dedicated Linux VM with the actual DualPI2 queue. The native Mac preview from `run-mac.sh` remains a separate preview without a controlled queue.

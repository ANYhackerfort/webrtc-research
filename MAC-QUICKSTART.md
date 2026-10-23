# Run the Mac video demo

**For the actual bottleneck experiment**, use [BOTTLENECK-QUICKSTART.md](BOTTLENECK-QUICKSTART.md):

```bash
cd ~/Desktop/webrtc-research
bash lab/run-bottleneck-mac.sh
```

The instructions below run the separate native Mac preview without a controlled queue.

Open Terminal:

```bash
cd ~/Desktop/webrtc-research
bash lab/install-canary-mac.sh
bash lab/run-mac.sh
```

You need Python 3. The installer skips installation if Canary is already present. The launcher downloads the news clip if needed and opens two Canary windows.

1. Click **Start video** in **SENDER**.
2. Watch the news video play in **RECEIVER**. Connection setup is automatic.
3. Watch the bitrate, RTT, and ECN graphs.
4. Download stats before stopping. Press **Ctrl+C** in Terminal to stop the demo.

```text
Video:     news_cif.y4m → Canary sender → Canary receiver
Feedback:                Canary sender ← Canary receiver
```

Blue shows ECT(1) packets; orange shows CE congestion marks. The sender controls its rate using SCReAM; the receiver reports packet arrivals and ECN marks.

**There is no controlled bottleneck in this Mac demo**, so CE can remain zero. To run the video through a DualPI2 queue, follow the Linux VM steps in [SCREAM-CANARY-GUIDE.md](SCREAM-CANARY-GUIDE.md).

To check the browser, open **`chrome://version`** in each window and confirm its executable path points to **Chrome Canary**. Current run logs are in the `runs/mac-...` folder printed by the launcher.

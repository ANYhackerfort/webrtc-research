# Run a SCReAM video flow with Chrome Canary

This lab sends `news_cif.y4m` as VP9 video between two Chrome Canary browsers. SCReAMv2 controls the sender's bitrate. The receiver displays the video and sends packet-arrival and ECN feedback back to the sender.

Choose one setup:

| Setup | What you can see |
| --- | --- |
| Mac bottleneck launcher | Actual DualPI2 queue inside a Linux VM, viewed from your Mac |
| Directly on your Mac | Video playback, bitrate, RTT, and ECN counters |
| Inside one Linux desktop VM | The same video flow passing through a rate limit and a DualPI2 bottleneck queue |

## A. Run with a bottleneck from your Mac

On an Apple Silicon Mac, run:

```bash
cd ~/Desktop/webrtc-research
bash lab/run-bottleneck-mac.sh
```

The launcher opens **http://127.0.0.1:18080/**. Video starts automatically between two Linux Canary browsers displayed in the page. Both browsers and the DualPI2 queue run inside one dedicated Linux VM on your Mac.

Use **250 kbit/s** or **1 Mbit/s** to change capacity. Click **Compare FIFO vs DualPI2** to measure a fresh 30-second call through each queue at the same capacity. Watch the CE counters and the result table.

```text
Linux VM: Canary sender → [rate limit + DualPI2] → Canary receiver
```

Stop the demo and VM with:

```bash
bash lab/run-bottleneck-mac.sh stop
```

See [BOTTLENECK-QUICKSTART.md](BOTTLENECK-QUICKSTART.md) for the controls and saved results.

## B. Run the video preview directly on your Mac

You need Python 3. Open Terminal and run:

```bash
cd ~/Desktop/webrtc-research
bash lab/install-canary-mac.sh
bash lab/run-mac.sh
```

The installer downloads Chrome Canary from Google if it is missing. The launcher downloads the video if needed and opens two separate Canary windows.

1. Click **Start video** in **SENDER**.
2. Watch the news video appear in **RECEIVER**. The browsers connect automatically.
3. Watch the live bitrate, RTT, and ECN graphs.
4. Click **Download stats and SDP** to save measurements.
5. Press **Ctrl+C** in Terminal to stop the demo.

```text
news_cif.y4m → Canary sender → Mac networking → Canary receiver
                            ← RTCP feedback ←
```

**This native Mac preview has no controlled bottleneck queue.** ECT(1) counts can increase while CE stays at zero. Use setup A to test the video through DualPI2.

## C. Set up the Linux experiment manually

### 1. Prepare a Linux desktop

Use Ubuntu 26.04 LTS Desktop on a Linux computer or in one VM on your Mac. On Apple Silicon, use an ARM64 guest; on an Intel Mac, use AMD64. Both Canary browsers and the queue run inside that same Linux desktop.

Copy this entire project folder into the Linux guest as `~/webrtc-research`. Open Terminal inside the Linux desktop:

```bash
bash
cd ~/webrtc-research
sudo apt update
sudo apt install -y curl python3 iproute2 iputils-ping ethtool tcpdump
mkdir -p media runs
```

### 2. Install Canary and download the video

```bash
arch=$(dpkg --print-architecture)
curl -fL "https://dl.google.com/linux/direct/google-chrome-canary_current_${arch}.deb" \
  -o chrome-canary.deb
sudo apt install -y ./chrome-canary.deb
curl -fL https://media.xiph.org/video/derf/y4m/news_cif.y4m \
  -o media/news_cif.y4m
```

Canary downloads come from [Google](https://www.google.com/chrome/canary/); the video comes from [Xiph](https://media.xiph.org/video/derf/).

### 3. Start the network and browsers

Create the bottleneck:

```bash
sudo bash lab/topology.sh up
```

Setup should print successful pings and show a `dualpi2` queue. If it fails, check the Linux kernel's DualPI2 support and the installed `iproute2` package before continuing.

In one Linux terminal:

```bash
cd ~/webrtc-research
bash lab/launch.sh tx
```

In a second Linux terminal:

```bash
cd ~/webrtc-research
bash lab/launch.sh rx
```

```text
                Everything runs inside Linux

Canary sender → [1 Mbit/s rate limit + DualPI2 queue] → Canary receiver
              ←────────── RTCP feedback ─────────────
```

The queue is on interface `rr0` inside `scream-router`. The browsers occupy separate network namespaces, forcing their video traffic through the router.

### 4. Connect the browsers

The Linux setup uses manual connection exchange:

1. In the sender, click **TX: create offer** and wait for the local description to be ready.
2. Copy its complete **Local description** JSON into the receiver's **Remote description** box.
3. In the receiver, click **RX: answer pasted offer** and wait for its local description.
4. Copy that complete JSON into the sender's remote-description box.
5. In the sender, click **TX: apply pasted answer**.

The connection should show `connected`, and the receiver should play the news video. Click its play control if needed.

### 5. Change the bottleneck capacity

While the video runs, lower the rate in a third Linux terminal:

```bash
cd ~/webrtc-research
sudo bash lab/topology.sh rate 250kbit
```

Watch the sender's bitrate and the receiver's CE counter. CE can increase when the queue becomes congested. After about 30 seconds, restore the rate:

```bash
sudo bash lab/topology.sh rate 1mbit
```

Inspect queue activity:

```bash
sudo bash lab/topology.sh status
```

Look for `dualpi2` and increasing packet counters. In the page's detailed statistics, the selected UDP path should connect `10.200.1.2` and `10.200.2.2`.

### 6. Save and stop

Download stats from both browser pages. Save the queue counters before cleanup:

```bash
sudo bash lab/topology.sh status > runs/queue-final.txt
```

Close both lab browsers, then remove the network:

```bash
sudo bash lab/topology.sh down
```

## Read the ECN display

| Display | Meaning |
| --- | --- |
| ECT(1) sent | Sender identifies packets for L4S treatment |
| ECT(1) received | Those markings reached the receiver |
| CE received | Packets arrived with a congestion mark |
| Blue/orange graph | ECT(1)/CE packet increments per sample, about one second |

Zero CE means no CE marks were observed. If traffic does not congest the queue, CE can stay at zero. Missing telemetry appears as unavailable.

## Confirm Canary and SCReAM

Open **`chrome://version`** in each browser. Check **Executable Path** points to Canary and **Command Line** includes:

```text
--force-fieldtrials=WebRTC-RFC8888CongestionControlFeedback/Enabled,offer:true/WebRTC-Bwe-ScreamV2/Enabled/
```

The scripts set this automatically. The test page also requires `ack ccfb` in the connection descriptions, confirming RFC 8888 feedback negotiation.

For execution evidence, inspect the current run's sender log for `ScreamV2:` messages with `target_rate` and congestion-window updates:

- Mac: `runs/mac-.../tx.stderr.log`
- Linux: `runs/tx-.../browser.stderr.log`

For this one-way video flow, SCReAM controls the sender; the receiver supplies feedback. ECT(1) and CE counters alone do not prove that SCReAM is processing feedback.

The Mac demo was tested with Canary 158.0.8120.0, and SCReAM execution was confirmed in its native logs. The Linux bottleneck setup still needs end-to-end validation.

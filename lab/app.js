'use strict';
const $ = id => document.getElementById(id);
const pc = new RTCPeerConnection({ iceServers: [], bundlePolicy: 'max-bundle' });
window.pc = pc;
const samples = [];
let stream;
let busy = false;
let previous = new Map();
let collecting = false;
const query = new URLSearchParams(location.search);
const role = query.get('role');
const automatic = query.get('auto') === '1';
if (query.get('mode') === 'mac') {
  document.title = `${role === 'tx' ? 'SENDER' : 'RECEIVER'} · Mac video demo`;
  document.querySelector('h1').textContent = role === 'tx' ? 'SENDER · news video' : 'RECEIVER · news video';
  $('mode').textContent = 'Mac video demo · direct local connection · no emulated bottleneck. ECN counters alone do not verify L4S end to end.';
  $('flow').textContent = 'news_cif.y4m → Sender / VP9 → Mac networking → Receiver / video. RTCP feedback returns to the sender.';
  $('preview').hidden = role === 'rx';
  $('received').hidden = role === 'tx';
}
if (query.get('mode') === 'vm') {
  document.title = `${role === 'tx' ? 'SENDER' : 'RECEIVER'} · Linux bottleneck`;
  document.querySelector('h1').textContent = role === 'tx' ? 'SENDER · SCReAM video' : 'RECEIVER · SCReAM video';
  $('mode').textContent = 'Linux VM experiment · traffic crosses the router queue. See the control panel for the active queue and rate.';
  $('flow').textContent = 'news_cif.y4m → Canary sender → Linux router / bottleneck → Canary receiver. RTCP feedback returns through the router.';
  $('preview').hidden = role === 'rx';
  $('received').hidden = role === 'tx';
}
if (automatic) {
  $('instructions').textContent = role === 'tx' ? 'Click Start video. The receiver connects automatically.' : 'Waiting for the sender. Click Start video in the other window.';
  $('offer').textContent = 'Start video';
  $('answer').hidden = true;
  $('apply').hidden = true;
  $('signaling').hidden = true;
  if (role === 'rx') $('offer').hidden = true;
}
$('offer').disabled = role === 'rx';
$('apply').disabled = role === 'rx';
$('answer').disabled = role === 'tx';
function status(message) { $('status').textContent = message; }
pc.onconnectionstatechange = () => {
  status(`Connection: ${pc.connectionState}`);
  if (automatic && pc.connectionState === 'connected') {
    $('instructions').textContent = role === 'tx'
      ? 'Sending the news clip to the other browser. Watch the measured graphs below.'
      : 'Receiving the news clip from the other browser. Watch the measured graphs below.';
  }
};
pc.ontrack = ({ track, streams }) => {
  $('received').srcObject = streams[0] || new MediaStream([track]);
  $('received').play().catch(() => status('Click play in the received video.'));
};
async function action(fn) {
  if (busy) return;
  busy = true;
  try { await fn(); } catch (error) { status(`${error.name}: ${error.message}`); console.error(error); }
  finally { busy = false; }
}
function waitForIce() {
  if (pc.iceGatheringState === 'complete') return Promise.resolve();
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pc.removeEventListener('icegatheringstatechange', check);
      reject(new Error('ICE gathering exceeded 20 seconds. Reload both pages.'));
    }, 20000);
    function check() {
      if (pc.iceGatheringState === 'complete') {
        clearTimeout(timer);
        pc.removeEventListener('icegatheringstatechange', check);
        resolve();
      }
    }
    pc.addEventListener('icegatheringstatechange', check);
    check();
  });
}
function requireCcfb(description) {
  if (!/^a=rtcp-fb:[\d*]+ ack ccfb\r?$/m.test(description.sdp)) {
    throw new Error('RFC 8888 ack ccfb is absent. Verify the field trials in both Canary processes.');
  }
}
async function publishLocal() {
  status('Gathering ICE candidates…');
  await waitForIce();
  requireCcfb(pc.localDescription);
  $('outgoing').value = JSON.stringify(pc.localDescription);
  status('Local description ready. Copy the complete JSON to the other browser.');
}
async function createOffer() {
  if (pc.getTransceivers().length) throw new Error('Reload both pages before making a new offer.');
  stream = await navigator.mediaDevices.getUserMedia({
    audio: false,
    video: { width: { exact: 352 }, height: { exact: 288 }, frameRate: { ideal: 30 } }
  });
  const track = stream.getVideoTracks()[0];
  $('preview').srcObject = stream;
  const codecs = RTCRtpSender.getCapabilities('video').codecs.filter(c => c.mimeType.toLowerCase() === 'video/vp9');
  if (!codecs.length) throw new Error('VP9 is unavailable in this build.');
  const transceiver = pc.addTransceiver(track, {
    direction: 'sendonly', streams: [stream],
    sendEncodings: [{ maxBitrate: 2000000, maxFramerate: 30, scaleResolutionDownBy: 1 }]
  });
  transceiver.setCodecPreferences(codecs);
  const params = transceiver.sender.getParameters();
  params.degradationPreference = 'maintain-resolution';
  await transceiver.sender.setParameters(params);
  await pc.setLocalDescription(await pc.createOffer());
  await publishLocal();
}
async function answerOffer() {
  const offer = JSON.parse($('incoming').value);
  if (offer.type !== 'offer') throw new Error('Paste the TX offer JSON.');
  requireCcfb(offer);
  await pc.setRemoteDescription(offer);
  await pc.setLocalDescription(await pc.createAnswer());
  await publishLocal();
}
async function applyAnswer() {
  const answer = JSON.parse($('incoming').value);
  if (answer.type !== 'answer') throw new Error('Paste the RX answer JSON.');
  requireCcfb(answer);
  await pc.setRemoteDescription(answer);
  status('Answer applied; connecting…');
}
async function signal(kind, description) {
  const url = `/signal?session=${encodeURIComponent(query.get('session') || '')}&kind=${kind}`;
  const response = await fetch(url, description ? {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(description)
  } : { cache: 'no-store' });
  if (!response.ok) throw new Error(`Signaling failed (${response.status}). Restart the Mac launcher.`);
  return response.json();
}
async function waitForSignal(kind) {
  const deadline = Date.now() + 180000;
  while (Date.now() < deadline && pc.connectionState !== 'closed') {
    const description = await signal(kind);
    if (description) return description;
    await new Promise(resolve => setTimeout(resolve, 400));
  }
  throw new Error('Connection setup stopped or timed out. Restart the Mac launcher.');
}
$('offer').onclick = () => action(async () => {
  await createOffer();
  if (automatic) {
    await signal('offer', pc.localDescription);
    status('Waiting for receiver…');
    $('incoming').value = JSON.stringify(await waitForSignal('answer'));
    await applyAnswer();
  }
});
$('answer').onclick = () => action(answerOffer);
$('apply').onclick = () => action(applyAnswer);
if (automatic && role === 'rx') action(async () => {
  status('Waiting for sender…');
  $('incoming').value = JSON.stringify(await waitForSignal('offer'));
  await answerOffer();
  await signal('answer', pc.localDescription);
});
const timer = setInterval(async () => {
  if (collecting || pc.connectionState === 'closed') return;
  collecting = true;
  try {
    const report = await pc.getStats();
    const raw = [...report.values()];
    const summary = [];
    for (const s of raw) {
      if ((s.type === 'outbound-rtp' || s.type === 'inbound-rtp') && s.kind === 'video') {
        const bytes = s.type === 'outbound-rtp' ? s.bytesSent : s.bytesReceived;
        const prev = previous.get(s.id);
        summary.push({
          direction: s.type, codec: report.get(s.codecId)?.mimeType,
          kbps: prev && s.timestamp > prev.timestamp ? Math.round(8 * (bytes - prev.bytes) / (s.timestamp - prev.timestamp)) : null,
          frameWidth: s.frameWidth, frameHeight: s.frameHeight, fps: s.framesPerSecond,
          targetBitrate: s.targetBitrate, qualityLimitationReason: s.qualityLimitationReason,
          packetsLost: s.packetsLost, framesDecoded: s.framesDecoded,
          packetsSentWithEct1: s.packetsSentWithEct1,
          packetsReceivedWithEct1: s.packetsReceivedWithEct1,
          packetsReceivedWithCe: s.packetsReceivedWithCe,
          jitterBufferDelay: s.jitterBufferDelay, jitterBufferEmittedCount: s.jitterBufferEmittedCount
        });
        previous.set(s.id, { bytes, timestamp: s.timestamp });
      }
      if (s.type === 'transport' && s.selectedCandidatePairId) {
        const pair = report.get(s.selectedCandidatePairId);
        if (pair) summary.push({
          selectedPair: pair.id, rttMs: pair.currentRoundTripTime * 1000,
          availableOutgoingBitrate: pair.availableOutgoingBitrate,
          local: report.get(pair.localCandidateId), remote: report.get(pair.remoteCandidateId)
        });
      }
    }
    if (pc.connectionState === 'connected') samples.push({ at: new Date().toISOString(), stats: raw });
    $('stats').textContent = JSON.stringify(summary, null, 2);
    window.dispatchEvent(new CustomEvent('labstats', { detail: { summary } }));
    if (query.get('record') === '1' && pc.connectionState === 'connected') {
      const response = await fetch(`/record?session=${encodeURIComponent(query.get('session') || '')}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ at: new Date().toISOString(), summary })
      });
      if (!response.ok) console.error(`Metric recording failed: ${response.status}`);
    }
  } catch (error) { console.error(error); }
  finally { collecting = false; }
}, 1000);
$('save').onclick = () => {
  const blob = new Blob([JSON.stringify({
    savedAt: new Date().toISOString(), userAgent: navigator.userAgent,
    localDescription: pc.localDescription, remoteDescription: pc.remoteDescription,
    captureSettings: stream?.getVideoTracks()[0]?.getSettings(), samples
  }, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = `scream-${role || 'peer'}-${Date.now()}.json`; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
};
$('stop').onclick = () => {
  clearInterval(timer); pc.close(); stream?.getTracks().forEach(t => t.stop());
  status('Stopped. Download the stats, then reload both pages for another run.');
};

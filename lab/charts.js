'use strict';
(() => {
  const history = [];
  let previousEcn;
  const fmt = value => Number.isFinite(value) ? String(Math.round(value)) : 'unavailable';
  function draw(id, key, color, secondKey, secondColor) {
    const svg = document.getElementById(id);
    const values = history.map(point => point[key]);
    const secondValues = secondKey ? history.map(point => point[secondKey]) : [];
    const measured = [...values, ...secondValues].filter(Number.isFinite);
    if (!measured.length) {
      svg.innerHTML = '<text x="20" y="75" fill="#52627a" font-size="14">Waiting for measurements</text>';
      return;
    }
    const max = Math.max(1, ...measured) * 1.1;
    function pathFor(series) {
      let path = '';
      let pen = false;
      series.forEach((value, i) => {
        if (!Number.isFinite(value)) { pen = false; return; }
        const x = 42 + i * 342 / 59;
        const y = 115 - value / max * 95;
        path += `${pen ? 'L' : 'M'}${x.toFixed(1)},${y.toFixed(1)} `;
        pen = true;
      });
      return path;
    }
    svg.innerHTML = `<path d="M42 18 V115 H386" fill="none" stroke="#a6b3c5"/>
      <text x="2" y="26" fill="#52627a" font-size="11">${Math.ceil(max)}</text>
      <text x="22" y="119" fill="#52627a" font-size="11">0</text>
      <text x="42" y="138" fill="#52627a" font-size="11">older</text>
      <text x="358" y="138" fill="#52627a" font-size="11">newer</text>
      <path d="${pathFor(values)}" fill="none" stroke="${color}" stroke-width="2.5"/>
      ${secondKey ? `<path d="${pathFor(secondValues)}" fill="none" stroke="${secondColor}" stroke-width="2.5"/>` : ''}`;
  }
  window.addEventListener('labstats', ({ detail: { summary } }) => {
    const video = summary.find(s => s.direction === 'outbound-rtp' || s.direction === 'inbound-rtp');
    const pair = summary.find(s => s.selectedPair);
    const sending = video?.direction === 'outbound-rtp';
    const ect = sending ? video.packetsSentWithEct1 : video?.packetsReceivedWithEct1;
    const ce = video?.packetsReceivedWithCe;
    const delta = (now, before) => Number.isFinite(now) && Number.isFinite(before) && now >= before ? now - before : null;
    history.push({ kbps: video?.kbps, rtt: pair?.rttMs,
      ectDelta: delta(ect, previousEcn?.ect), ceDelta: delta(ce, previousEcn?.ce) });
    previousEcn = { ect, ce };
    if (history.length > 60) history.shift();
    draw('bitrate-plot', 'kbps', '#176ad3');
    draw('rtt-plot', 'rtt', '#a054bd');
    draw('ecn-plot', 'ectDelta', '#176ad3', 'ceDelta', '#b64f04');
    document.getElementById('ect1-label').textContent = sending ? 'ECT(1) packets sent' : 'ECT(1) packets received';
    document.getElementById('ect1-count').textContent = fmt(ect);
    document.getElementById('ce-count').textContent = sending ? 'See receiver' : fmt(ce);
    const markedTotal = ect + ce;
    document.getElementById('ce-share').textContent = !sending && Number.isFinite(ect) && Number.isFinite(ce) && markedTotal > 0
      ? `${(100 * ce / markedTotal).toFixed(2)}%` : sending ? 'See receiver' : 'unavailable';
    document.getElementById('ecn-status').textContent = sending
      ? 'ECT(1) identifies packets sent as L4S-capable. Check the RECEIVER window for congestion-experienced (CE) marks.'
      : Number.isFinite(ce) && ce > 0
        ? 'CE-marked packets have reached this receiver. Also verify the sender controller and its feedback response before claiming end-to-end L4S.'
        : ce === 0
          ? 'No CE marks observed. This direct Mac connection has no emulated congestion-marking queue; ECT(1) alone does not prove end-to-end L4S.'
          : 'CE telemetry is unavailable in this build or no inbound video stream is reporting yet.';
    if (ce === 0 && new URLSearchParams(location.search).get('mode') !== 'mac') {
      document.getElementById('ecn-status').textContent = 'No CE marks observed. Check the DualPI2 queue, selected network path, and offered load; ECT(1) alone does not prove end-to-end L4S.';
    }
    const parts = [
      `Video: ${video?.codec || 'waiting'} · ${fmt(video?.fps)} fps`,
      `ECT(1) sent: ${fmt(video?.packetsSentWithEct1)} · received: ${fmt(video?.packetsReceivedWithEct1)} · CE received: ${fmt(video?.packetsReceivedWithCe)}`
    ];
    if (pair) parts.push(`Selected path: ${pair.local?.address || pair.local?.ip || '?'}:${pair.local?.port || '?'} → ${pair.remote?.address || pair.remote?.ip || '?'}:${pair.remote?.port || '?'} (${pair.local?.protocol || '?'})`);
    document.getElementById('readouts').textContent = parts.join('\n');
    document.getElementById('readouts').style.whiteSpace = 'pre-line';
  });
  draw('bitrate-plot', 'kbps', '#176ad3');
  draw('rtt-plot', 'rtt', '#a054bd');
  draw('ecn-plot', 'ectDelta', '#176ad3', 'ceDelta', '#b64f04');
})();

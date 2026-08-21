const CHANNEL_LABELS = { pulse1: 'Pulse 1', pulse2: 'Pulse 2', wave: 'Wave', noise: 'Noise' };
const hexByte = (value) => `0x${value.toString(16).padStart(2, '0').toUpperCase()}`;

function drawApuMaster(apu) {
  const master = Object.entries(apu.master).map(([name, value]) => `${name.toUpperCase()} ${hexByte(value)}`);
  document.getElementById('apu-master').innerHTML =
    `<span class="${apu.enabled ? '' : 'off'}">power ${apu.enabled ? 'on' : 'off'}</span> · ` +
    `${master.join(' · ')} · ${apu.mode} · queue ${apu.audio_queue_size}`;
}

function formatValue(value) {
  if (value === null || value === undefined) return '—';
  if (value === true) return 'yes';
  if (value === false) return 'no';
  return value;
}

const fieldRows = (entries) =>
  entries.map(([name, value]) => `<b>${name.replace(/_/g, ' ')}</b><span>${formatValue(value)}</span>`).join('');

// Nested stages become their own titled group so leaf names stay short enough for a card.
function channelCard(key, channel) {
  const scalars = [];
  const groups = [];

  for (const [name, value] of Object.entries(channel)) {
    if (name === 'registers' || name === 'scope' || value === null) continue;
    if (typeof value === 'object') {
      groups.push(`<h5>${name.replace(/_/g, ' ')}</h5><div class="fields">${fieldRows(Object.entries(value))}</div>`);
    } else {
      scalars.push([name, value]);
    }
  }

  const registers = Object.entries(channel.registers)
    .map(([name, value]) => `<span><b>${name.toUpperCase()}</b>${hexByte(value)}</span>`)
    .join('');

  return `<div class="channel${channel.enabled ? '' : ' off'}"><h4>${CHANNEL_LABELS[key]}</h4>` +
         `<canvas class="mini-scope" data-channel="${key}" width="240" height="52"></canvas>` +
         `<div class="fields">${fieldRows(scalars)}</div>` +
         `<div class="registers">${registers}</div>${groups.join('')}</div>`;
}

function drawApuChannels(apu) {
  document.getElementById('apu-channels').innerHTML =
    Object.entries(apu.channels).map(([key, channel]) => channelCard(key, channel)).join('');

  // Canvases only exist once the markup above is in the DOM.
  document.querySelectorAll('.mini-scope').forEach((canvas) => {
    const channel = apu.channels[canvas.dataset.channel];
    plotWaveform(canvas, channel.scope || [], themeColor('--chart-1'));
  });
}

// Signed waveform centred on zero, autoscaled to its own peak.
function plotWaveform(canvas, samples, stroke) {
  const ctx = canvas.getContext('2d');
  const mid = canvas.height / 2;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.strokeStyle = themeColor('--line');
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(0, mid);
  ctx.lineTo(canvas.width, mid);
  ctx.stroke();

  if (samples.length === 0) return 0;

  const peak = Math.max(...samples.map(Math.abs), 0.001);
  ctx.strokeStyle = stroke;
  ctx.beginPath();
  samples.forEach((sample, index) => {
    const x = (index / (samples.length - 1 || 1)) * canvas.width;
    const y = mid - (sample / peak) * (mid - 2);
    if (index === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  });
  ctx.stroke();
  return peak;
}

function drawScope(apu) {
  // The mixer's range depends on NR50 and on the high-pass filter, so the axis is labelled
  // with the measured peak rather than an assumed full scale.
  const peak = plotWaveform(document.getElementById('scope'), apu.scope || [], themeColor('--accent'));
  document.getElementById('scope-peak').textContent = `+${peak.toFixed(2)}`;
  document.getElementById('scope-trough').textContent = `−${peak.toFixed(2)}`;
}

function drawWaveRam(apu) {
  const canvas = document.getElementById('wave-ram');
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  const bytes = apu.wave_ram || [];
  if (bytes.length === 0) return;

  ctx.strokeStyle = themeColor('--line');
  ctx.lineWidth = 1;
  [0.25, 0.5, 0.75].forEach((ratio) => {
    const y = Math.round(canvas.height * ratio) + 0.5;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(canvas.width, y);
    ctx.stroke();
  });

  // Each byte holds two 4-bit samples, high nibble first.
  const nibbles = bytes.flatMap((byte) => [(byte >> 4) & 0xf, byte & 0xf]);
  const barWidth = canvas.width / nibbles.length;
  const position = apu.channels.wave.position;
  const barColor = themeColor('--chart-2');
  const cursorColor = themeColor('--chart-alert');

  nibbles.forEach((value, index) => {
    const height = (value / 15) * (canvas.height - 1);
    ctx.fillStyle = index === position ? cursorColor : barColor;
    ctx.fillRect(index * barWidth, canvas.height - height, Math.max(barWidth - 0.5, 1), height);
  });
}

function renderApu(apu) {
  if (!apu) return;
  drawApuMaster(apu);
  drawApuChannels(apu);
  drawScope(apu);
  drawWaveRam(apu);
}

const CHANNEL_LABELS = { pulse1: 'Pulse 1', pulse2: 'Pulse 2', wave: 'Wave', noise: 'Noise' };
const CHANNEL_NUMBERS = { pulse1: 1, pulse2: 2, wave: 3, noise: 4 };
const PERIOD_REGISTERS = { pulse1: ['nr13', 'nr14'], pulse2: ['nr23', 'nr24'], wave: ['nr33', 'nr34'] };
const ENVELOPE_REGISTERS = { pulse1: 'nr12', pulse2: 'nr22', noise: 'nr42' };
const CONTROL_REGISTERS = { pulse1: 'nr14', pulse2: 'nr24', wave: 'nr34', noise: 'nr44' };
const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const WAVE_LEVELS = [0, 1, 0.5, 0.25];
const DUTY_PATTERNS = [
  [0, 0, 0, 0, 0, 0, 0, 1],
  [1, 0, 0, 0, 0, 0, 0, 1],
  [1, 0, 0, 0, 1, 1, 1, 1],
  [0, 1, 1, 1, 1, 1, 1, 0],
];
const DUTY_LABELS = ['12.5%', '25%', '50%', '75%'];

const hexByte = (value) => `0x${value.toString(16).padStart(2, '0').toUpperCase()}`;
const hexWord = (value) => `0x${value.toString(16).padStart(4, '0').toUpperCase()}`;

function formatValue(value) {
  if (value === null || value === undefined) return '—';
  if (value === true) return 'yes';
  if (value === false) return 'no';
  return value;
}

// Pulse and wave step the same 11-bit period at different rates; noise is a shift/divisor pair.
function channelFrequency(key, registers) {
  if (key === 'noise') {
    const nr43 = registers.nr43 || 0;
    const code = nr43 & 0x07;
    return 262144 / ((code === 0 ? 0.5 : code) * 2 ** (nr43 >> 4));
  }

  const [low, high] = PERIOD_REGISTERS[key];
  const period = (registers[low] || 0) | (((registers[high] || 0) & 0x07) << 8);
  if (period >= 2048) return null;
  return (key === 'wave' ? 65536 : 131072) / (2048 - period);
}

function noteName(hz) {
  if (!hz || !Number.isFinite(hz) || hz <= 0) return '';
  const midi = Math.round((12 * Math.log2(hz / 440)) + 69);
  if (midi < 12 || midi > 127) return '';
  return `${NOTE_NAMES[midi % 12]}${Math.floor(midi / 12) - 1}`;
}

const badge = (on) => `<span class="dot${on ? ' on' : ''}">${on ? 'on' : 'off'}</span>`;

// Levels live in the meters above; these lines carry the mechanism the meters cannot show.
const STAGES = {
  length_timer: { abbr: 'LT', line: (v) => `${badge(v.enabled)} Frame Seq: ${v.frame_sequencer_step}` },
  volume_envelope: { abbr: 'VE', line: (v) => `Step: ${v.envelope_sweep_step}` },
  period_divider: {
    abbr: 'PD',
    line: (v) => `÷${v.clock_divider} · ${v.current_period_div}` +
                 `${v.next_period_div === null ? '' : ` → ${v.next_period_div}`}`,
  },
  sweep: {
    abbr: 'SW',
    line: (v) => `${badge(v.enabled)} ${v.step}/${v.period} · Shadow: ${v.shadow_frequency}`,
  },
  lfsr: {
    abbr: 'LFSR',
    line: (v) => `${v.mode} · ${v.mode === 'short' ? '7' : '15'}-bit · ${hexWord(v.value)} · LSB: ${v.lsb}`,
  },
  noise_timer: { abbr: 'NT', line: (v) => `${v.period}/${v.target}` },
};

const STAGE_TITLES = {
  length_timer: 'Length timer',
  volume_envelope: 'Volume envelope',
  period_divider: 'Period divider',
  sweep: 'Frequency sweep',
  lfsr: 'Linear feedback shift register',
  noise_timer: 'Noise timer',
};

const stageAbbr = (name) => name.split('_').map((word) => word[0].toUpperCase()).join('');
const stageLine = (name, value) =>
  (STAGES[name] ? STAGES[name].line(value) : Object.values(value).map(formatValue).join(' · '));

function stageTitle(name, value) {
  const detail = Object.entries(value)
    .map(([field, fieldValue]) => `${field.replace(/_/g, ' ')}: ${formatValue(fieldValue)}`)
    .join('\n');
  return `${STAGE_TITLES[name] || name.replace(/_/g, ' ')}\n${detail}`;
}

function dutyPath(dutyCycle) {
  const pattern = DUTY_PATTERNS[dutyCycle] || DUTY_PATTERNS[0];
  let path = `M0 ${pattern[0] ? 1 : 9}`;
  pattern.forEach((bit, index) => {
    const y = bit ? 1 : 9;
    path += ` L${index * 8} ${y} L${(index + 1) * 8} ${y}`;
  });
  return path;
}

const stageNames = (channel) =>
  Object.entries(channel)
    .filter(([name, value]) => name !== 'registers' && name !== 'scope' && value !== null && typeof value === 'object')
    .map(([name]) => name);

function cardMarkup(key, channel) {
  const isPulse = key.startsWith('pulse');
  const levelLabel = key === 'wave' ? 'level' : 'volume';

  const stages = stageNames(channel)
    .map((name) => `<b data-stage-abbr="${name}">${STAGES[name] ? STAGES[name].abbr : stageAbbr(name)}</b>` +
                   `<span data-stage="${name}"></span>`)
    .join('');

  const meter = (name, label) =>
    `<div class="meter"><b>${label}</b><span class="track"><i data-meter="${name}"></i></span>` +
    `<span class="meter-value" data-meter-value="${name}"></span></div>`;

  return `<div class="channel" data-card="${key}">
    <h4>${CHANNEL_LABELS[key]}</h4>
    <div class="summary">
      <div class="status">
        <span class="dot" data-dot="on">on</span>
        <span class="dot" data-dot="dac">dac</span>
        <span class="dot" data-dot="len">len</span>
        <span class="pan"><i data-pan="left">L</i><i data-pan="right">R</i></span>
      </div>
      <div class="pitch"><b data-pitch-hz></b><span data-pitch-note></span></div>
      ${meter('level', levelLabel)}
      ${meter('length', 'length')}
      ${isPulse ? '<div class="duty-row"><svg class="duty" viewBox="0 0 64 10" preserveAspectRatio="none">' +
                  '<path data-duty-path /></svg><span data-duty-label></span></div>' : ''}
    </div>
    <canvas class="mini-scope" data-scope="${key}" width="240" height="52"></canvas>
    <div class="registers" data-registers></div>
    <div class="stages">${stages}</div>
  </div>`;
}

let cards = null;

function buildCards(apu) {
  const container = document.getElementById('apu-channels');
  container.innerHTML = Object.entries(apu.channels).map(([key, channel]) => cardMarkup(key, channel)).join('');
  cards = {};
  Object.keys(apu.channels).forEach((key) => {
    cards[key] = container.querySelector(`[data-card="${key}"]`);
  });
}

const setText = (node, text) => { if (node && node.textContent !== String(text)) node.textContent = text; };
const setClass = (node, name, on) => { if (node) node.classList.toggle(name, Boolean(on)); };

function updateCard(key, channel, master, root) {
  const number = CHANNEL_NUMBERS[key];
  const control = channel.registers[CONTROL_REGISTERS[key]] || 0;

  root.classList.toggle('off', !channel.enabled);
  setClass(root.querySelector('[data-dot="on"]'), 'on', channel.enabled);
  setClass(root.querySelector('[data-dot="dac"]'), 'on', channel.dac_enabled);
  setClass(root.querySelector('[data-dot="len"]'), 'on', control & 0x40);
  setClass(root.querySelector('[data-pan="left"]'), 'on', (master.nr51 >> (number + 3)) & 1);
  setClass(root.querySelector('[data-pan="right"]'), 'on', (master.nr51 >> (number - 1)) & 1);

  const hz = channelFrequency(key, channel.registers);
  setText(root.querySelector('[data-pitch-hz]'), hz === null ? '—' : `${hz.toFixed(1)} Hz`);
  setText(root.querySelector('[data-pitch-note]'), hz === null ? '' : noteName(hz));

  updateLevel(key, channel, root);
  updateLength(channel, root);
  updateDuty(key, channel, root);

  setText(root.querySelector('[data-registers]'), '');
  root.querySelector('[data-registers]').innerHTML = Object.entries(channel.registers)
    .map(([name, value]) => `<span><b>${name.toUpperCase()}</b>${hexByte(value)}</span>`)
    .join('');

  stageNames(channel).forEach((name) => {
    const node = root.querySelector(`[data-stage="${name}"]`);
    const line = stageLine(name, channel[name]);
    if (node.innerHTML !== line) node.innerHTML = line;
    // Both the abbreviation and the values carry the tooltip; updating the attribute in place
    // is what lets it survive between snapshots.
    const title = stageTitle(name, channel[name]);
    node.title = title;
    root.querySelector(`[data-stage-abbr="${name}"]`).title = title;
  });
}

function updateLevel(key, channel, root) {
  const ratio = key === 'wave'
    ? (WAVE_LEVELS[channel.output_level] ?? 0)
    : (channel.volume_envelope.volume / 15);
  const text = key === 'wave'
    ? (channel.output_level === null ? '—' : `${WAVE_LEVELS[channel.output_level] * 100}%`)
    : `${channel.volume_envelope.volume}/15 ${(channel.registers[ENVELOPE_REGISTERS[key]] & 0x08) ? '↑' : '↓'}`;

  root.querySelector('[data-meter="level"]').style.width = `${Math.max(0, Math.min(1, ratio)) * 100}%`;
  setText(root.querySelector('[data-meter-value="level"]'), text);
}

function updateLength(channel, root) {
  const { length_timer: current, length_timer_target: target } = channel.length_timer;
  root.querySelector('[data-meter="length"]').style.width = `${Math.max(0, Math.min(1, current / target)) * 100}%`;
  setText(root.querySelector('[data-meter-value="length"]'), `${current}/${target}`);
}

function updateDuty(key, channel, root) {
  if (!key.startsWith('pulse')) return;
  root.querySelector('[data-duty-path]').setAttribute('d', dutyPath(channel.duty_cycle));
  setText(root.querySelector('[data-duty-label]'), DUTY_LABELS[channel.duty_cycle]);
}

function drawApuMaster(apu) {
  const master = Object.entries(apu.master).map(([name, value]) => `${name.toUpperCase()} ${hexByte(value)}`);
  document.getElementById('apu-master').innerHTML =
    `<span class="${apu.enabled ? '' : 'off'}">power ${apu.enabled ? 'on' : 'off'}</span> · ` +
    `${master.join(' · ')} · ${apu.mode} · queue ${apu.audio_queue_size}`;
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
  setText(document.getElementById('scope-peak'), `+${peak.toFixed(2)}`);
  setText(document.getElementById('scope-trough'), `−${peak.toFixed(2)}`);
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

function drawApuChannels(apu) {
  if (!cards || Object.keys(cards).join() !== Object.keys(apu.channels).join()) buildCards(apu);

  Object.entries(apu.channels).forEach(([key, channel]) => {
    const root = cards[key];
    updateCard(key, channel, apu.master, root);
    plotWaveform(root.querySelector(`[data-scope="${key}"]`), channel.scope || [], themeColor('--chart-1'));
  });
}

function renderApu(apu) {
  if (!apu) return;
  drawApuMaster(apu);
  drawApuChannels(apu);
  drawScope(apu);
  drawWaveRam(apu);
}

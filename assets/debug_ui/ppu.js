const SHADES = [[224, 232, 208], [136, 160, 120], [72, 96, 72], [24, 32, 24]];
const el = (id) => document.getElementById(id);
let snapshot = null;

const paletteFrom = (byte) => [0, 1, 2, 3].map((i) => (byte >> (i * 2)) & 3);

function putTile(image, pixels, ox, oy, palette) {
  for (let row = 0; row < 8; row += 1) {
    for (let col = 0; col < 8; col += 1) {
      const shade = SHADES[palette[pixels[row * 8 + col]]];
      const offset = ((oy + row) * image.width + ox + col) * 4;
      image.data[offset] = shade[0];
      image.data[offset + 1] = shade[1];
      image.data[offset + 2] = shade[2];
      image.data[offset + 3] = 255;
    }
  }
}

function drawTiles(ppu) {
  const canvas = el('tiles');
  const ctx = canvas.getContext('2d');
  const image = ctx.createImageData(canvas.width, canvas.height);
  const palette = el('grey').checked ? paletteFrom(ppu.registers.bgp) : [0, 1, 2, 3];

  ppu.tiles.forEach((pixels, index) => {
    putTile(image, pixels, (index % 16) * 8, Math.floor(index / 16) * 8, palette);
  });
  ctx.putImageData(image, 0, 0);
}

function tileIndexFor(mapValue, signedAddressing) {
  if (!signedAddressing) return mapValue;
  return mapValue < 128 ? mapValue + 256 : mapValue;
}

function drawTilemap(ppu) {
  const canvas = el('tilemap');
  const ctx = canvas.getContext('2d');
  const image = ctx.createImageData(256, 256);
  const palette = paletteFrom(ppu.registers.bgp);
  const which = Number(document.querySelector('input[name=map]:checked').value);
  const signedAddressing = (ppu.registers.lcdc & 0x10) === 0;

  ppu.tilemaps[which].forEach((value, cell) => {
    const pixels = ppu.tiles[tileIndexFor(value, signedAddressing)];
    putTile(image, pixels, (cell % 32) * 8, Math.floor(cell / 32) * 8, palette);
  });
  ctx.putImageData(image, 0, 0);

  if (el('show-scroll').checked) drawScroll(ctx, ppu);
  if (el('show-window').checked) drawWindow(ctx, ppu);
}

function drawScroll(ctx, ppu) {
  const { scx, scy } = ppu.registers;
  ctx.strokeStyle = '#ff5f56';
  ctx.lineWidth = 1;
  // The viewport wraps around the 256x256 map, so it can need up to four rectangles.
  for (const dx of [0, -256]) {
    for (const dy of [0, -256]) {
      ctx.strokeRect(scx + dx + 0.5, scy + dy + 0.5, 160, 144);
    }
  }
}

function drawWindow(ctx, ppu) {
  const { lcdc, wx, wy } = ppu.registers;
  if ((lcdc & 0x20) === 0) return;
  ctx.strokeStyle = '#57c7ff';
  ctx.lineWidth = 1;
  ctx.strokeRect(wx - 7 + 0.5, wy + 0.5, 160, 144);
}

function drawRegisters(ppu) {
  const hex = (value) => `0x${value.toString(16).padStart(2, '0').toUpperCase()}`;
  const rows = Object.entries(ppu.registers).map(([name, value]) => `<b>${name}</b><span>${hex(value)}</span>`);
  rows.push(`<b>mode</b><span>${ppu.mode}</span>`);
  el('registers').innerHTML = rows.join('');
}

function drawOam(ppu) {
  const header = '<tr><th>#</th><th>Y</th><th>X</th><th>tile</th><th>flags</th></tr>';
  const rows = ppu.oam.map((sprite, index) => {
    const flags = [
      sprite.flags & 0x80 ? 'pri' : '',
      sprite.flags & 0x40 ? 'yflip' : '',
      sprite.flags & 0x20 ? 'xflip' : '',
      sprite.flags & 0x10 ? 'obp1' : 'obp0',
    ].filter(Boolean).join(' ');
    return `<tr><td>${index}</td><td>${sprite.y}</td><td>${sprite.x}</td>` +
           `<td>${sprite.tile}</td><td>${flags}</td></tr>`;
  });
  el('oam').innerHTML = header + rows.join('');
}

function render() {
  if (!snapshot) return;
  drawTiles(snapshot.ppu);
  drawTilemap(snapshot.ppu);
  drawRegisters(snapshot.ppu);
  drawOam(snapshot.ppu);
}

el('tiles').addEventListener('mousemove', (event) => {
  const rect = el('tiles').getBoundingClientRect();
  const col = Math.floor(((event.clientX - rect.left) / rect.width) * 16);
  const row = Math.floor(((event.clientY - rect.top) / rect.height) * 24);
  const index = row * 16 + col;
  el('tile-info').textContent = `tile ${index} @ 0x${(0x8000 + index * 16).toString(16).toUpperCase()}`;
});

document.querySelectorAll('input').forEach((input) => input.addEventListener('change', render));

const source = new EventSource('/events');
source.onopen = () => { el('status').textContent = 'connected'; };
source.onerror = () => { el('status').textContent = 'disconnected'; };
source.onmessage = (event) => {
  snapshot = JSON.parse(event.data);
  render();
};

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

const SCREEN_WIDTH = 160;
const SCREEN_HEIGHT = 144;
// Which sprite painted each screen pixel, so hovering can name it.
const spriteOwners = new Int16Array(SCREEN_WIDTH * SCREEN_HEIGHT);

const onScreen = (sprite) => sprite.y > 0 && sprite.y < 160 && sprite.x > 0 && sprite.x < 168;

function paintSprite(image, ppu, sprite, index, height) {
  const palette = paletteFrom(sprite.flags & 0x10 ? ppu.registers.obp1 : ppu.registers.obp0);
  const xFlip = (sprite.flags & 0x20) !== 0;
  const yFlip = (sprite.flags & 0x40) !== 0;
  const baseTile = height === 16 ? sprite.tile & 0xfe : sprite.tile;

  for (let row = 0; row < height; row += 1) {
    const y = sprite.y - 16 + row;
    if (y < 0 || y >= SCREEN_HEIGHT) continue;
    const sourceRow = yFlip ? height - 1 - row : row;
    const tile = ppu.tiles[baseTile + (sourceRow >= 8 ? 1 : 0)];
    if (!tile) continue;

    for (let col = 0; col < 8; col += 1) {
      const x = sprite.x - 8 + col;
      if (x < 0 || x >= SCREEN_WIDTH) continue;
      const value = tile[(sourceRow % 8) * 8 + (xFlip ? 7 - col : col)];
      if (value === 0) continue; // colour 0 is transparent for sprites

      const shade = SHADES[palette[value]];
      const pixel = y * SCREEN_WIDTH + x;
      const offset = pixel * 4;
      image.data[offset] = shade[0];
      image.data[offset + 1] = shade[1];
      image.data[offset + 2] = shade[2];
      image.data[offset + 3] = 255;
      spriteOwners[pixel] = index;
    }
  }
}

function drawSprites(ppu) {
  const canvas = el('sprites');
  const ctx = canvas.getContext('2d');
  const image = ctx.createImageData(SCREEN_WIDTH, SCREEN_HEIGHT);
  spriteOwners.fill(-1);

  const height = ppu.registers.lcdc & 0x04 ? 16 : 8;
  const visible = ppu.oam.map((sprite, index) => ({ sprite, index })).filter(({ sprite }) => onScreen(sprite));

  // DMG priority: smallest X wins, OAM index breaks ties. Painting worst-first puts the
  // winner on top.
  visible
    .slice()
    .sort((a, b) => b.sprite.x - a.sprite.x || b.index - a.index)
    .forEach(({ sprite, index }) => paintSprite(image, ppu, sprite, index, height));

  ctx.putImageData(image, 0, 0);
  el('sprite-count').textContent = `${visible.length}/40 on screen · ${height === 16 ? '8×16' : '8×8'}`;
}

function render() {
  if (!snapshot) return;
  drawTiles(snapshot.ppu);
  drawTilemap(snapshot.ppu);
  drawRegisters(snapshot.ppu);
  drawSprites(snapshot.ppu);
  renderApu(snapshot.apu);
}

el('sprites').addEventListener('mousemove', (event) => {
  if (!snapshot) return;
  const rect = el('sprites').getBoundingClientRect();
  const x = Math.floor(((event.clientX - rect.left) / rect.width) * SCREEN_WIDTH);
  const y = Math.floor(((event.clientY - rect.top) / rect.height) * SCREEN_HEIGHT);
  const index = spriteOwners[y * SCREEN_WIDTH + x];

  if (index < 0) {
    el('sprite-info').textContent = 'hover a sprite';
    return;
  }

  const sprite = snapshot.ppu.oam[index];
  const flags = [
    sprite.flags & 0x80 ? 'behind bg' : '',
    sprite.flags & 0x40 ? 'yflip' : '',
    sprite.flags & 0x20 ? 'xflip' : '',
    sprite.flags & 0x10 ? 'obp1' : 'obp0',
  ].filter(Boolean).join(' · ');
  el('sprite-info').textContent = `tile ${sprite.tile} · x=${sprite.x} y=${sprite.y} · ${flags}`;
});

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

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

function putTileRGB(image, pixels, ox, oy, colors, xFlip, yFlip) {
  for (let row = 0; row < 8; row += 1) {
    const srcRow = yFlip ? 7 - row : row;
    for (let col = 0; col < 8; col += 1) {
      const srcCol = xFlip ? 7 - col : col;
      const [r, g, b] = colors[pixels[(srcRow * 8) + srcCol]];
      const offset = ((oy + row) * image.width + ox + col) * 4;
      image.data[offset] = r;
      image.data[offset + 1] = g;
      image.data[offset + 2] = b;
      image.data[offset + 3] = 255;
    }
  }
}

function drawTilemapCgb(image, ppu, which, signedAddressing) {
  const attrs = ppu.tilemap_attrs[which];

  ppu.tilemaps[which].forEach((value, cell) => {
    const attr = attrs[cell];
    const tileSet = attr & 0x08 ? ppu.tiles_bank1 : ppu.tiles;
    const pixels = tileSet[tileIndexFor(value, signedAddressing)];
    const colors = ppu.bg_colors[attr & 0x07];
    putTileRGB(image, pixels, (cell % 32) * 8, Math.floor(cell / 32) * 8, colors, !!(attr & 0x20), !!(attr & 0x40));
  });
}

function drawTilemapDmg(image, ppu, which, signedAddressing) {
  const palette = paletteFrom(ppu.registers.bgp);

  ppu.tilemaps[which].forEach((value, cell) => {
    const pixels = ppu.tiles[tileIndexFor(value, signedAddressing)];
    putTile(image, pixels, (cell % 32) * 8, Math.floor(cell / 32) * 8, palette);
  });
}

function drawTilemap(ppu) {
  const canvas = el('tilemap');
  const ctx = canvas.getContext('2d');
  const image = ctx.createImageData(256, 256);
  const which = Number(document.querySelector('input[name=map]:checked').value);
  const signedAddressing = (ppu.registers.lcdc & 0x10) === 0;

  if (ppu.cgb) {
    drawTilemapCgb(image, ppu, which, signedAddressing);
  } else {
    drawTilemapDmg(image, ppu, which, signedAddressing);
  }
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

const regHexByte = (value) => `0x${value.toString(16).padStart(2, '0').toUpperCase()}`;
const regBadge = (on, label) => `<span class="dot${on ? ' on' : ''}">${label}</span>`;

function lcdcBadges(lcdc) {
  const bit = (n) => (lcdc >> n) & 1;
  return [
    regBadge(bit(7), 'LCD'),
    regBadge(bit(5), 'WIN'),
    regBadge(bit(1), 'OBJ'),
    regBadge(bit(0), 'BG/PRI'),
    regBadge(true, `BG MAP ${bit(3) ? '9C00' : '9800'}`),
    regBadge(true, `WIN MAP ${bit(6) ? '9C00' : '9800'}`),
    regBadge(true, `DATA ${bit(4) ? '8000' : '8800'}`),
    regBadge(true, `OBJ ${bit(2) ? '8x16' : '8x8'}`),
  ].join('');
}

function statBadges(stat) {
  const bit = (n) => (stat >> n) & 1;
  return [
    regBadge(bit(2), 'LYC=LY'),
    regBadge(bit(3), 'INT M0'),
    regBadge(bit(4), 'INT M1'),
    regBadge(bit(5), 'INT M2'),
    regBadge(bit(6), 'INT LYC'),
  ].join('');
}

function paletteSwatches(byte) {
  return paletteFrom(byte)
    .map((shadeIndex) => `<span class="swatch" style="background: rgb(${SHADES[shadeIndex].join(',')})"></span>`)
    .join('');
}

function palettesGroup(label, colorSets) {
  const rows = colorSets.map((colors, index) => {
    const blank = colors.every(([r, g, b]) => r === 0xff && g === 0xff && b === 0xff);
    const swatches = colors.map(([r, g, b]) => `<span class="swatch" style="background: rgb(${r},${g},${b})"></span>`).join('');
    return `<div class="palette-row${blank ? ' blank' : ''}"><span>${index}</span><span class="swatches">${swatches}</span>${blank ? '<span>untouched</span>' : ''}</div>`;
  }).join('');
  return `<div><p class="palette-group-label">${label}</p>${rows}</div>`;
}

function drawPalettes(ppu) {
  el('palettes-panel').hidden = !ppu.cgb;
  if (!ppu.cgb) return;

  el('palettes').innerHTML = `<div class="palette-groups">${palettesGroup('BG', ppu.bg_colors)}${palettesGroup('OBJ', ppu.obj_colors)}</div>`;
}

function regBlock(label, value, extra = '') {
  return `<div class="reg-block"><div class="reg-head"><b>${label}</b><span>${value}</span></div>${extra}</div>`;
}

function drawRegisters(ppu) {
  const { lcdc, stat, scy, scx, ly, lyc, bgp, obp0, obp1, wy, wx } = ppu.registers;
  const lycMatch = ly === lyc ? ' <span class="dot on">MATCH</span>' : '';
  const speedBadges = `${regBadge(ppu.speed.double, ppu.speed.double ? '2x' : '1x')}${regBadge(ppu.speed.armed, 'ARMED')}`;

  el('registers').innerHTML = [
    regBlock('SPEED', '', `<div class="reg-badges">${speedBadges}</div>`),
    regBlock('LCDC', `${regHexByte(lcdc)} · mode ${ppu.mode}`, `<div class="reg-badges">${lcdcBadges(lcdc)}</div>`),
    regBlock('STAT', regHexByte(stat), `<div class="reg-badges">${statBadges(stat)}</div>`),
    regBlock('LY / LYC', `${ly} / ${lyc}${lycMatch}`),
    regBlock('SCX / SCY', `${scx}, ${scy}`),
    regBlock('WX / WY', `${wx}, ${wy}`),
    regBlock('BGP', '', `<div class="reg-badges">${paletteSwatches(bgp)}</div>`),
    regBlock('OBP0', '', `<div class="reg-badges">${paletteSwatches(obp0)}</div>`),
    regBlock('OBP1', '', `<div class="reg-badges">${paletteSwatches(obp1)}</div>`),
  ].join('');
}

function drawDma(dma) {
  const hexWord = (value) => `0x${value.toString(16).padStart(4, '0').toUpperCase()}`;
  const rows = [
    `<b>active</b><span>${dma.active ? 'yes' : 'no'}</span>`,
    `<b>mode</b><span>${dma.mode}</span>`,
    `<b>source</b><span>${hexWord(dma.source)}</span>`,
    `<b>destination</b><span>${hexWord(dma.destination)}</span>`,
    `<b>blocks</b><span>${dma.remaining_blocks}/${dma.requested_blocks}</span>`,
  ];
  el('dma').innerHTML = rows.join('');
}

const SCREEN_WIDTH = 160;
const SCREEN_HEIGHT = 144;
// Which sprite painted each screen pixel, so hovering can name it.
const spriteOwners = new Int16Array(SCREEN_WIDTH * SCREEN_HEIGHT);

const onScreen = (sprite) => sprite.y > 0 && sprite.y < 160 && sprite.x > 0 && sprite.x < 168;

function paintSprite(image, ppu, sprite, index, height) {
  const xFlip = (sprite.flags & 0x20) !== 0;
  const yFlip = (sprite.flags & 0x40) !== 0;
  const baseTile = height === 16 ? sprite.tile & 0xfe : sprite.tile;

  const cgb = ppu.cgb;
  const tileSet = cgb && sprite.flags & 0x08 ? ppu.tiles_bank1 : ppu.tiles;
  const colors = cgb ? ppu.obj_colors[sprite.flags & 0x07] : null;
  const palette = cgb ? null : paletteFrom(sprite.flags & 0x10 ? ppu.registers.obp1 : ppu.registers.obp0);

  for (let row = 0; row < height; row += 1) {
    const y = sprite.y - 16 + row;
    if (y < 0 || y >= SCREEN_HEIGHT) continue;
    const sourceRow = yFlip ? height - 1 - row : row;
    const tile = tileSet[baseTile + (sourceRow >= 8 ? 1 : 0)];
    if (!tile) continue;

    for (let col = 0; col < 8; col += 1) {
      const x = sprite.x - 8 + col;
      if (x < 0 || x >= SCREEN_WIDTH) continue;
      const value = tile[(sourceRow % 8) * 8 + (xFlip ? 7 - col : col)];
      if (value === 0) continue; // colour 0 is transparent for sprites

      const shade = cgb ? colors[value] : SHADES[palette[value]];
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
  drawPalettes(snapshot.ppu);
  drawDma(snapshot.dma);
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

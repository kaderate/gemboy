# frozen_string_literal: true

# Renders a real screenshot alongside ScreenSnapshot's decoded cell classification (colors +
# letters + an in-image legend), for human review of the tile catalog's current accuracy on one
# screen -- see ZELDA_BACKLOG.md's navigation overhaul. Not wired into any test; a visual-review
# tool, run manually.
#
# Usage: bundle exec ruby lib/game_agents/experiments/render_screen_snapshot.rb [catalog_path] [checkpoint_method] [out_path]
$LOAD_PATH.unshift(File.expand_path('../..', __dir__))
require 'game_agents/zelda/scenarios'
require 'game_agents/zelda/screen_snapshot'
require 'game_agents/zelda/tile_catalog'
require 'utils/png_writer'
require_relative 'pixel_font'

catalog_path = ARGV[0] || File.expand_path('../zelda/data/tile_catalog.json', __dir__)
checkpoint = (ARGV[1] || 'front_yard').to_sym
out_path = ARGV[2] || '/tmp/screen_snapshot.png'

catalog = Zelda::TileCatalog.load(catalog_path)
_, ppu, _, mmu, = Zelda::Scenarios.public_send(checkpoint)
cells = Zelda::ScreenSnapshot.build(ppu, mmu, catalog)

# PngWriter/framebuffer pixels are packed as R | (G<<8) | (B<<16), not the usual 0xRRGGBB -- convert.
def rgb(hex) = ((hex >> 16) & 0xFF) | (hex & 0xFF00) | ((hex & 0xFF) << 16)

COLORS = {
  unexplored: rgb(0x808080),
  walkable: rgb(0x4CAF50),
  probably_walkable: rgb(0xA5D6A7),
  wall: rgb(0x6D4C33),
  door: rgb(0x3F72C4),
  water: rgb(0x2196F3),
  ledge: rgb(0xFF9800),
  hole: rgb(0x111111),
  decorative: rgb(0x9C27B0),
  mixed_unknown: rgb(0xE0C300),
  hud: rgb(0xCCCCCC)
}.freeze

LETTERS = {
  unexplored: '?', walkable: 'W', probably_walkable: 'p', wall: '#', door: 'D',
  water: '~', ledge: 'L', hole: 'O', decorative: '*', mixed_unknown: 'X', hud: 'H'
}.freeze

LEGEND_ORDER = %i[unexplored probably_walkable walkable wall door water ledge hole decorative mixed_unknown hud].freeze
LEGEND_LABEL = {
  unexplored: 'INCONNU', probably_walkable: 'PROBABLE', walkable: 'OK', wall: 'MUR', door: 'PORTE',
  water: 'EAU', ledge: 'REBORD', hole: 'TROU', decorative: 'DECO', mixed_unknown: 'MIXTE', hud: 'HUD'
}.freeze

# -- left: real screenshot, scaled --
scale = 6
width = 160
height = 144
pixels = ppu.framebuffer.pixels_frame
shot_w = width * scale
shot_h = height * scale
shot = Array.new(shot_w * shot_h)
(0...height).each do |y|
  (0...width).each do |x|
    c = pixels[(y * width) + x]
    scale.times { |dy| scale.times { |dx| shot[((((y * scale) + dy) * shot_w) + (x * scale) + dx)] = c } }
  end
end

# -- right: abstracted grid, one flat-colored cell per gameplay cell (16x16 game px -> same scale
# so it lines up 1:1 under the screenshot's own pixel grid) --
cell_px = 16 * scale
grid_w = Zelda::ScreenSnapshot::CELL_COLS * cell_px
grid_h = Zelda::ScreenSnapshot::CELL_ROWS * cell_px
grid = Array.new(grid_w * grid_h)
cells.each do |c|
  color = COLORS.fetch(c.status)
  ox = c.col * cell_px
  oy = c.row * cell_px
  (0...cell_px).each do |dy|
    (0...cell_px).each do |dx|
      # thin darker border so cells are visually separated
      border = dx.zero? || dy.zero? || dx == cell_px - 1 || dy == cell_px - 1
      grid[((oy + dy) * grid_w) + ox + dx] = border ? (color & 0xFEFEFE) >> 1 : color
    end
  end
end

# -- legend strip: one swatch + letter + word per category, in a fixed order --
legend_h = 40
legend_w = grid_w
legend = Array.new(legend_w * legend_h, rgb(0xF0F0F0))
swatch = 22
lx = 6
LEGEND_ORDER.each do |status|
  color = COLORS.fetch(status)
  (0...swatch).each { |dy| (0...swatch).each { |dx| legend[((9 + dy) * legend_w) + lx + dx] = color } }
  draw_glyph!(legend, legend_w, lx + 7, 12, LETTERS.fetch(status), rgb(0xFFFFFF), px: 2)
  draw_text!(legend, legend_w, lx + swatch + 4, 14, LEGEND_LABEL.fetch(status), rgb(0x222222), px: 2)
  lx += swatch + 4 + (LEGEND_LABEL.fetch(status).length * 7) + 14
end

# -- letter label inside each grid cell, matching the legend --
cells.each do |c|
  color = COLORS.fetch(c.status)
  brightness = ((color & 0xFF) + ((color >> 8) & 0xFF) + ((color >> 16) & 0xFF)) / 3
  label_color = brightness > 140 ? rgb(0x1A1A1A) : rgb(0xFFFFFF)
  ox = c.col * cell_px
  oy = c.row * cell_px
  draw_glyph!(grid, grid_w, ox + (cell_px / 2) - 3, oy + (cell_px / 2) - 5, LETTERS.fetch(c.status), label_color, px: 2)
end

# -- compose: screenshot on top, grid below, legend at the bottom, small gaps --
gap = 16
total_w = [shot_w, grid_w].max
total_h = shot_h + gap + grid_h + gap + legend_h
canvas = Array.new(total_w * total_h, rgb(0xFFFFFF))
(0...shot_h).each { |y| (0...shot_w).each { |x| canvas[(y * total_w) + x] = shot[(y * shot_w) + x] } }
(0...grid_h).each { |y| (0...grid_w).each { |x| canvas[((y + shot_h + gap) * total_w) + x] = grid[(y * grid_w) + x] } }
legend_y0 = shot_h + gap + grid_h + gap
(0...legend_h).each { |y| (0...legend_w).each { |x| canvas[((y + legend_y0) * total_w) + x] = legend[(y * legend_w) + x] } }

PngWriter.write(out_path, canvas, width: total_w, height: total_h)
puts "saved #{out_path}"
puts "tally: #{cells.map(&:status).tally}"

# frozen_string_literal: true

# Regenerates the "Carnet de Koholint" progress report (world map + per-screen grids) from the
# CURRENT contents of data/screen_maps/*.json and data/tile_catalog.json, plus a fresh screenshot
# of each mapped screen. Reusable on request: rerun this any time exploration has moved forward,
# then hand the output file to the Artifact tool (republish to the same URL to keep the link
# alive) -- this script does the mechanical data/asset work, publishing itself stays a Claude-side
# step since only Claude can call the Artifact tool.
#
# Usage: bundle exec ruby lib/game_agents/experiments/generate_koholint_report.rb [output.html]
require 'erb'
require 'json'
require 'base64'
$LOAD_PATH.unshift(File.expand_path('../..', __dir__))
require 'game_agents/zelda/scenarios'
require 'utils/png_writer'

# One entry per screen worth showing on the map. `checkpoint_method` drives a fresh screenshot;
# `screen_map` (nil for a not-yet-(re)mapped interior) drives the stats + per-screen grid.
SCREENS = {
  'starting_house' => { checkpoint_method: :after_shield_interior, screen_map: nil,
                        note: 'Point de départ -- pas encore recartographié avec ScreenMap' },
  'front_yard' => { checkpoint_method: :front_yard, screen_map: 'overworld_front_yard' },
  'screen2' => { checkpoint_method: :overworld_screen2, screen_map: 'overworld_screen2' },
  'screen3' => { checkpoint_method: :villager_screen, screen_map: 'overworld_screen3' }
}.freeze

# Curated by hand -- the mechanical stats/grids/screenshots below regenerate automatically, but
# "what did we learn" is a narrative call, not something to infer from a diff. Update this array
# when something new is confirmed, fixed, or found stuck.
FINDINGS = [
  { tag: 'Corrigé', cls: '',
    html: 'Le glissement de coin après un "blocked" faussait la case d\'arrivée mesurée -- ' \
          '<code>probe()</code> vérifie maintenant la vraie position d\'atterrissage au lieu de ' \
          'la supposer inchangée.' },
  { tag: 'Corrigé', cls: '',
    html: '<code>find_link</code> confondait Tarkin avec Link juste après son dialogue (pose du ' \
          'sprite non reconnue) -- la liste d\'exclusion correcte règle le problème.' },
  { tag: 'Non résolu', cls: 'blocked',
    html: 'La case <code>[6,7]</code> d\'overworld_screen3 reste inatteignable à chaque tentative ' \
          '-- villageois errant suspecté. Elle est ignorée sans bloquer le reste de l\'écran.' },
  { tag: 'Piste ouverte', cls: 'open',
    html: 'La détection de sortie d\'écran se base sur une distance en pixels (&gt;40px). Dans ' \
          'une pièce ouverte (starting_house), un déplacement normal peut dépasser ce seuil sans ' \
          'vraie sortie -- il faudrait lire SCX/SCY plutôt que la distance brute.' }
].freeze

def snap_base64(ppu, scale: 4)
  pixels = ppu.framebuffer.pixels_frame
  width = 160
  height = 144
  out_w = width * scale
  out_h = height * scale
  out = Array.new(out_w * out_h)
  (0...height).each do |y|
    (0...width).each do |x|
      color = pixels[(y * width) + x]
      scale.times { |dy| scale.times { |dx| out[((((y * scale) + dy) * out_w) + (x * scale) + dx)] = color } }
    end
  end
  tmp = "/tmp/koholint_report_snap_#{Process.pid}.png"
  PngWriter.write(tmp, out, width: out_w, height: out_h)
  Base64.strict_encode64(File.binread(tmp)).force_encoding(Encoding::UTF_8)
ensure
  File.delete(tmp) if tmp && File.exist?(tmp)
end

def edge_short(edges)
  %w[up down left right].each_with_object({}) do |dir, h|
    h[dir[0]] = edges[dir] if edges[dir]
  end
end

data_dir = File.expand_path('../zelda/data', __dir__)
catalog = JSON.parse(File.read(File.join(data_dir, 'tile_catalog.json')))

images = {}
screens_js = {}
screen_meta = {}

SCREENS.each do |key, cfg|
  puts "snapping #{key}..."
  _cpu, ppu = Zelda::Scenarios.public_send(cfg[:checkpoint_method])
  images[key] = snap_base64(ppu)

  next unless cfg[:screen_map]

  grid_path = File.join(data_dir, 'screen_maps', "#{cfg[:screen_map]}.json")
  grid = JSON.parse(File.read(grid_path))
  cells = grid['cells'].map { |c| { r: c['row'], c: c['col'], e: edge_short(c['edges']) } }
  screens_js[key] = cells
  confirmed = cells.count { |c| c[:e].any? }
  pending = cells.size - confirmed
  screen_meta[key] = { name: cfg[:screen_map], note: cfg[:note] || "#{confirmed} cases confirmées, #{pending} repérées" }
end

total_tested = screens_js.values.flatten.count { |c| c[:e].any? }
total_pending = screens_js.values.flatten.count { |c| c[:e].empty? }

template = ERB.new(File.read(File.join(__dir__, 'koholint_report_template.html.erb'), encoding: 'UTF-8'))

findings_html = FINDINGS.map do |f|
  "<div class=\"finding #{f[:cls]}\"><span class=\"tag\">#{f[:tag]}</span>#{f[:html]}</div>"
end.join("\n")

html = template.result_with_hash(
  screens: SCREENS,
  images: images,
  total_tested: total_tested,
  total_pending: total_pending,
  catalog_size: catalog.size,
  screens_json: JSON.generate(screens_js),
  screen_meta_json: JSON.generate(screen_meta),
  findings_html: findings_html,
  generated_at: "carte générée le #{Time.now.strftime('%-d %B %Y à %Hh%M')}"
)

output_path = ARGV[0] || '/tmp/koholint_report.html'
File.write(output_path, html)
puts "saved -> #{output_path} (#{html.bytesize} bytes)"

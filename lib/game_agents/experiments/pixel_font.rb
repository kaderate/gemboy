# frozen_string_literal: true

# Minimal 3x5 pixel font, just the glyphs render_screen_snapshot.rb's legend needs. '#' = lit,
# '.' = background. Not a general-purpose text renderer -- no lowercase distinct from uppercase,
# no accents.
FONT_3X5 = {
  '?' => ['###', '..#', '.#.', '...', '.#.'],
  'p' => ['##.', '#.#', '##.', '#..', '#..'],
  'W' => ['#.#', '#.#', '#.#', '###', '#.#'],
  '#' => ['.#.', '###', '.#.', '###', '.#.'],
  'D' => ['##.', '#.#', '#.#', '#.#', '##.'],
  '~' => ['...', '.#.', '#.#', '...', '...'],
  'L' => ['#..', '#..', '#..', '#..', '###'],
  'O' => ['.#.', '#.#', '#.#', '#.#', '.#.'],
  '*' => ['#.#', '.#.', '###', '.#.', '#.#'],
  'X' => ['#.#', '.#.', '.#.', '.#.', '#.#'],
  'A' => ['.#.', '#.#', '###', '#.#', '#.#'],
  'B' => ['##.', '#.#', '##.', '#.#', '##.'],
  'C' => ['.##', '#..', '#..', '#..', '.##'],
  'E' => ['###', '#..', '##.', '#..', '###'],
  'I' => ['###', '.#.', '.#.', '.#.', '###'],
  'M' => ['#.#', '###', '#.#', '#.#', '#.#'],
  'N' => ['#.#', '##.', '#.#', '#.#', '#.#'],
  'P' => ['##.', '#.#', '##.', '#..', '#..'],
  'R' => ['##.', '#.#', '##.', '#.#', '#.#'],
  'S' => ['.##', '#..', '.#.', '..#', '##.'],
  'T' => ['###', '.#.', '.#.', '.#.', '.#.'],
  'U' => ['#.#', '#.#', '#.#', '#.#', '###'],
  'V' => ['#.#', '#.#', '#.#', '#.#', '.#.'],
  'K' => ['#.#', '#.#', '##.', '#.#', '#.#'],
  'H' => ['#.#', '#.#', '###', '#.#', '#.#'],
  'G' => ['.##', '#..', '#.#', '#.#', '.##'],
  'F' => ['###', '#..', '##.', '#..', '#..'],
  'Y' => ['#.#', '#.#', '.#.', '.#.', '.#.'],
  ' ' => ['...', '...', '...', '...', '...'],
  '.' => ['...', '...', '...', '.#.', '...']
}.freeze

def draw_glyph!(canvas, canvas_w, x0, y0, char, color, px: 2)
  glyph = FONT_3X5[char.upcase] || FONT_3X5[' ']
  glyph.each_with_index do |row, ry|
    row.each_char.with_index do |c, rx|
      next unless c == '#'

      px.times do |dy|
        px.times do |dx|
          x = x0 + (rx * px) + dx
          y = y0 + (ry * px) + dy
          canvas[(y * canvas_w) + x] = color if x >= 0 && x < canvas_w && y >= 0 && y < canvas.size / canvas_w
        end
      end
    end
  end
end

def draw_text!(canvas, canvas_w, x0, y0, text, color, px: 2, spacing: 1)
  cursor = x0
  text.each_char do |c|
    draw_glyph!(canvas, canvas_w, cursor, y0, c, color, px:)
    cursor += (3 * px) + spacing
  end
end

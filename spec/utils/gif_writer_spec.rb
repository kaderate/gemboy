require_relative '../../lib/utils/gif_writer'
require_relative '../../lib/screen'
require 'tempfile'

RSpec.describe GifWriter do
  it 'writes a valid animated GIF file with the correct dimensions' do
    white = Screen.pack_color(0xFF, 0xFF, 0xFF, 0xFF)
    black = Screen.pack_color(0x00, 0x00, 0x00, 0xFF)
    red = Screen.pack_color(0xFF, 0x00, 0x00, 0xFF)

    frame1 = [white, black, black, white]
    frame2 = [black, white, white, black]
    frame3 = [red, red, red, red]

    Tempfile.create(['test', '.gif']) do |file|
      described_class.write(file.path, [frame1, frame2, frame3], width: 2, height: 2, delay_cs: 5)

      bytes = File.binread(file.path)
      expect(bytes[0, 6]).to eq('GIF89a'.b)

      width, height = bytes[6, 4].unpack('v2')
      expect(width).to eq(2)
      expect(height).to eq(2)

      expect(bytes[-1].unpack1('C')).to eq(0x3B) # trailer
    end
  end

  it 'accepts a single-frame GIF' do
    pixels = [Screen.pack_color(0x10, 0x20, 0x30, 0xFF)] * (8 * 8)

    Tempfile.create(['test', '.gif']) do |file|
      described_class.write(file.path, [pixels], width: 8, height: 8)

      bytes = File.binread(file.path)
      expect(bytes[0, 6]).to eq('GIF89a'.b)
      expect(bytes[-1].unpack1('C')).to eq(0x3B)
    end
  end

  it 'raises ArgumentError when more than 256 unique colors appear across all frames' do
    pixels = Array.new(257) { |i| Screen.pack_color(i & 0xFF, (i >> 8) & 0xFF, 0x00, 0xFF) }

    Tempfile.create(['test', '.gif']) do |file|
      expect do
        described_class.write(file.path, [pixels], width: 257, height: 1)
      end.to raise_error(ArgumentError, /unique colors/)
    end
  end

  it 'round-trips pixel data faithfully through a minimal LZW decoder' do
    # Enough colors and pixels to force several code-size bumps, exercising GIF's LZW
    # "early change" quirk (the decoder's dictionary trails the encoder's by one code).
    colors = Array.new(10) { |i| Screen.pack_color(i * 20, (i * 37) % 256, (i * 53) % 256, 0xFF) }
    srand(42)
    width = 40
    height = 36
    frames = Array.new(3) { Array.new(width * height) { colors.sample } }

    Tempfile.create(['test', '.gif']) do |file|
      described_class.write(file.path, frames, width: width, height: height)

      decoded_frames = decode_gif(file.path)
      expect(decoded_frames.size).to eq(frames.size)
      decoded_frames.each_with_index do |decoded, i|
        expect(decoded).to eq(frames[i].map { |c| GifWriter.send(:pack_rgb, c) })
      end
    end
  end
end

# Minimal GIF89a reader, just enough to verify GifWriter's own output round-trips: parses the
# global color table and each frame's LZW-compressed indexed data back into packed RGB bytes.
def decode_gif(path)
  bytes = File.binread(path)
  pos = 6
  width, height, packed = bytes[pos, 5].unpack('v2C')
  pos += 7
  gct_size = 2 << (packed & 0x07)
  gct = bytes[pos, gct_size * 3].bytes.each_slice(3).map { |rgb| rgb.pack('C3') }
  pos += gct_size * 3

  frames = []
  while pos < bytes.bytesize
    marker = bytes[pos].unpack1('C')
    break if marker == 0x3B # trailer

    if marker == 0x21
      pos = skip_gif_extension(bytes, pos)
    else
      frame, pos = read_gif_image(bytes, pos, width, height, gct)
      frames << frame
    end
  end
  frames
end

def skip_gif_extension(bytes, pos)
  pos += 2
  loop do
    size = bytes[pos].unpack1('C')
    pos += 1 + size
    break if size.zero?
  end
  pos
end

def read_gif_image(bytes, pos, width, height, gct)
  pos += 10 # image descriptor: separator + left/top/width/height + packed byte
  min_code_size = bytes[pos].unpack1('C')
  pos += 1
  data = +''.b
  while (size = bytes[pos].unpack1('C')) != 0
    data << bytes[pos + 1, size]
    pos += 1 + size
  end
  pos += 1
  indices = lzw_decode(data, min_code_size)
  [indices.first(width * height).map { |idx| gct[idx] }, pos]
end

def gif_bit_reader(data)
  bitpos = 0
  lambda do |size|
    val = 0
    size.times do |i|
      byte_idx = (bitpos + i) / 8
      bit = byte_idx < data.bytesize ? (data.getbyte(byte_idx) >> ((bitpos + i) % 8)) & 1 : 0
      val |= bit << i
    end
    bitpos += size
    val
  end
end

def reset_lzw_decode_table(clear_code, eoi_code, min_code_size)
  table = Array.new(clear_code) { |i| [i] }
  [table, eoi_code + 1, min_code_size + 1]
end

def lzw_decode(data, min_code_size)
  clear_code = 1 << min_code_size
  eoi_code = clear_code + 1
  read = gif_bit_reader(data)
  table, next_code, code_size = reset_lzw_decode_table(clear_code, eoi_code, min_code_size)

  out = []
  prev = nil
  loop do
    code = read.call(code_size)
    if code == clear_code
      table, next_code, code_size = reset_lzw_decode_table(clear_code, eoi_code, min_code_size)
      prev = nil
      next
    end
    break if code == eoi_code

    entry = table[code] || (prev + [prev.first])
    out.concat(entry)
    if prev
      table[next_code] = prev + [entry.first]
      next_code += 1
      code_size += 1 if next_code >= (1 << code_size) && code_size < 12
    end
    prev = entry
  end
  out
end

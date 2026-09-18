# GifWriter is a minimal animated GIF encoder for dumping recorded gameplay frames to disk (debugging/testing).
class GifWriter
  MAX_COLORS = 256

  # frames is an Array of pixel-frames, each in PngWriter's format: packed RGBA ints (see
  # Screen.pack_color), alpha dropped. delay_cs is the per-frame delay in centiseconds.
  def self.write(path, frames, width:, height:, delay_cs: 10)
    palette, indexed_frames = build_palette(frames, width, height)
    color_bits = bits_for(palette.size)

    File.open(path, 'wb') do |f|
      f.write('GIF89a'.b)
      f.write([width, height, 0xF0 | (color_bits - 1), 0, 0].pack('v2C3'))
      f.write(pack_gct(palette, 1 << color_bits))
      f.write(loop_forever_extension) # loop the recording indefinitely, like a typical screen-capture GIF

      indexed_frames.each do |indices|
        f.write(graphic_control_extension(delay_cs))
        f.write(image_descriptor(width, height))
        f.write(lzw_encode(indices, color_bits))
      end

      f.write("\x3B".b) # trailer
    end
  end

  def self.build_palette(frames, width, height)
    color_to_index = {}
    indexed_frames = frames.map do |pixels|
      Array.new(width * height) { |i| color_to_index[pixels[i]] ||= color_to_index.size }
    end

    if color_to_index.size > MAX_COLORS
      raise ArgumentError, "GIF global color table overflow: #{color_to_index.size} unique colors across all " \
                           "frames (max #{MAX_COLORS}); color quantization is not implemented"
    end

    palette = Array.new(color_to_index.size)
    color_to_index.each { |color, index| palette[index] = pack_rgb(color) }
    [palette, indexed_frames]
  end

  def self.pack_rgb(color) = [color & 0xFF, (color >> 8) & 0xFF, (color >> 16) & 0xFF].pack('C3')

  # LZW minimum code size can't be below 2, so the palette is padded to at least 4 entries.
  def self.bits_for(color_count)
    bits = 1
    bits += 1 while (1 << bits) < color_count
    [bits, 2].max
  end

  def self.pack_gct(palette, gct_size)
    data = +''.b
    gct_size.times { |i| data << (palette[i] || "\x00\x00\x00".b) }
    data
  end

  def self.loop_forever_extension
    "\x21\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00".b
  end

  def self.graphic_control_extension(delay_cs)
    [0x21, 0xF9, 4, 0x00, delay_cs, 0x00, 0x00].pack('C3CvCC')
  end

  def self.image_descriptor(width, height)
    [0x2C, 0, 0, width, height, 0x00].pack('Cv4C')
  end

  def self.lzw_encode(indices, color_bits)
    color_bits.chr.b + sub_blockify(pack_codes(lzw_codes(indices, color_bits)))
  end

  def self.lzw_codes(indices, color_bits)
    clear_code = 1 << color_bits
    eoi_code = clear_code + 1
    dict, next_code, code_size = reset_lzw_dict(clear_code, eoi_code, color_bits)

    codes = [[clear_code, code_size]]
    w = nil
    indices.each do |k|
      wk = w ? w + [k] : [k]
      next w = wk if dict.key?(wk)

      codes << [dict[w], code_size]
      dict[wk] = next_code
      next_code += 1
      if next_code >= 4096
        codes << [clear_code, code_size]
        dict, next_code, code_size = reset_lzw_dict(clear_code, eoi_code, color_bits)
      elsif next_code > (1 << code_size) && code_size < 12 # GIF's "early change": decoder tracks the dict one code behind
        code_size += 1
      end
      w = [k]
    end
    codes << [dict[w], code_size] if w
    codes << [eoi_code, code_size]
    codes
  end

  def self.reset_lzw_dict(clear_code, eoi_code, color_bits)
    dict = {}
    clear_code.times { |i| dict[[i]] = i }
    [dict, eoi_code + 1, color_bits + 1]
  end

  def self.pack_codes(codes)
    bitstream = 0
    bitcount = 0
    bytes = +''.b
    codes.each do |code, size|
      bitstream |= code << bitcount
      bitcount += size
      while bitcount >= 8
        bytes << (bitstream & 0xFF)
        bitstream >>= 8
        bitcount -= 8
      end
    end
    bytes << (bitstream & 0xFF) if bitcount > 0
    bytes
  end

  def self.sub_blockify(bytes)
    out = +''.b
    bytes.bytes.each_slice(255) do |slice|
      out << slice.size.chr << slice.pack('C*')
    end
    out << "\x00".b
  end

  private_class_method :build_palette, :pack_rgb, :bits_for, :pack_gct, :loop_forever_extension,
                       :graphic_control_extension, :image_descriptor, :lzw_encode, :lzw_codes, :reset_lzw_dict,
                       :pack_codes, :sub_blockify
end

# frozen_string_literal: true

require 'zlib'

# Minimal PNG decoder, counterpart of PngWriter, used to load the reference screenshots a ROM
# result is compared against. Only handles what those references are stored as, non-interlaced:
# 2-bit grayscale (dmg-acid2) and 4-bit palettized (cgb-acid2). Grayscale pixels are returned
# raw (0 = black), palettized ones as [r, g, b] triplets resolved through PLTE.
module PngReader
  class UnsupportedFormat < StandardError; end

  Image = Struct.new(:width, :height, :pixels, :color_type, keyword_init: true) do
    def palettized? = color_type == INDEXED
  end

  MAGIC = "\x89PNG\r\n\x1A\n".b
  GRAYSCALE = 0
  INDEXED = 3
  SUPPORTED_DEPTHS = { GRAYSCALE => 2, INDEXED => 4 }.freeze

  class << self
    def read(path)
      bytes = File.binread(path)
      raise UnsupportedFormat, "#{path}: not a PNG file" unless bytes.start_with?(MAGIC)

      chunks = parse_chunks(bytes)
      width, height, color_type, depth = check_header(path, chunks['IHDR'])
      pixels = decode(Zlib::Inflate.inflate(chunks['IDAT']), width, height, depth)
      pixels = resolve_palette(path, pixels, chunks['PLTE']) if color_type == INDEXED

      Image.new(width:, height:, pixels:, color_type:)
    end

    private

    def parse_chunks(bytes)
      offset = MAGIC.bytesize
      chunks = Hash.new { |hash, key| hash[key] = +''.b }
      while offset < bytes.bytesize
        length = bytes[offset, 4].unpack1('N')
        type = bytes[offset + 4, 4]
        chunks[type] << bytes[offset + 8, length]
        offset += length + 12 # length + type + data + CRC
      end
      chunks
    end

    def check_header(path, header)
      width, height, depth, color_type, _compression, _filter, interlace = header.unpack('N2C5')
      unless SUPPORTED_DEPTHS[color_type] == depth && interlace.zero?
        raise UnsupportedFormat,
              "#{path}: expected a non-interlaced 2-bit grayscale or 4-bit palettized PNG, " \
              "got depth #{depth}, color type #{color_type}, interlace #{interlace}"
      end

      [width, height, color_type, depth]
    end

    def resolve_palette(path, indexes, palette)
      colors = palette.bytes.each_slice(3).to_a
      raise UnsupportedFormat, "#{path}: missing or empty PLTE chunk" if colors.empty?

      indexes.map do |index|
        colors[index] || raise(UnsupportedFormat, "#{path}: palette index #{index} out of range")
      end
    end

    def decode(raw, width, height, depth)
      stride = (((width * depth) + 7) / 8)
      previous = Array.new(stride, 0)

      (0...height).flat_map do |y|
        offset = y * (stride + 1)
        line = unfilter(raw.getbyte(offset), raw.byteslice(offset + 1, stride).bytes, previous)
        previous = line
        unpack_line(line, width, depth)
      end
    end

    # Sub-byte depths filter over bytes, so the "previous pixel" is simply the previous byte.
    def unfilter(filter, line, previous)
      line.each_with_index do |byte, i|
        left = i.zero? ? 0 : line[i - 1]
        up = previous[i]
        line[i] = (byte + filter_addend(filter, left, up, i.zero? ? 0 : previous[i - 1])) & 0xFF
      end
    end

    def filter_addend(filter, left, up, up_left)
      case filter
      when 0 then 0
      when 1 then left
      when 2 then up
      when 3 then (left + up) / 2
      when 4 then paeth(left, up, up_left)
      else raise UnsupportedFormat, "unknown scanline filter #{filter}"
      end
    end

    def paeth(left, up, up_left)
      estimate = left + up - up_left
      to_left = (estimate - left).abs
      to_up = (estimate - up).abs
      to_up_left = (estimate - up_left).abs

      return left if to_left <= to_up && to_left <= to_up_left

      to_up <= to_up_left ? up : up_left
    end

    def unpack_line(line, width, depth)
      per_byte = 8 / depth
      mask = (1 << depth) - 1

      line.flat_map { |byte| Array.new(per_byte) { |i| (byte >> (8 - (depth * (i + 1)))) & mask } }.first(width)
    end
  end
end

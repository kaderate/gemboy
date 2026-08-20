# frozen_string_literal: true

require 'zlib'

# Minimal PNG decoder, counterpart of PngWriter, used to load the reference screenshots a ROM
# result is compared against. Only handles what those references are stored as: 2-bit grayscale,
# non-interlaced. Pixel values are returned raw (0 = black), not as DMG palette indexes.
module PngReader
  class UnsupportedFormat < StandardError; end

  Image = Struct.new(:width, :height, :pixels, keyword_init: true)

  MAGIC = "\x89PNG\r\n\x1A\n".b
  GRAYSCALE = 0
  BIT_DEPTH = 2
  PIXELS_PER_BYTE = 8 / BIT_DEPTH

  class << self
    def read(path)
      bytes = File.binread(path)
      raise UnsupportedFormat, "#{path}: not a PNG file" unless bytes.start_with?(MAGIC)

      chunks = parse_chunks(bytes)
      width, height = check_header(path, chunks['IHDR'])

      Image.new(width:, height:, pixels: decode(Zlib::Inflate.inflate(chunks['IDAT']), width, height))
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
      unless depth == BIT_DEPTH && color_type == GRAYSCALE && interlace.zero?
        raise UnsupportedFormat,
              "#{path}: expected a non-interlaced #{BIT_DEPTH}-bit grayscale PNG, " \
              "got depth #{depth}, color type #{color_type}, interlace #{interlace}"
      end

      [width, height]
    end

    def decode(raw, width, height)
      stride = (width + PIXELS_PER_BYTE - 1) / PIXELS_PER_BYTE
      previous = Array.new(stride, 0)

      (0...height).flat_map do |y|
        offset = y * (stride + 1)
        line = unfilter(raw.getbyte(offset), raw.byteslice(offset + 1, stride).bytes, previous)
        previous = line
        unpack_line(line, width)
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

    def unpack_line(line, width)
      line.flat_map { |byte| Array.new(PIXELS_PER_BYTE) { |i| (byte >> (6 - (2 * i))) & 0b11 } }.first(width)
    end
  end
end

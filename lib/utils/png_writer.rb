require 'zlib'

# PngWriter is a minimal truecolor PNG encoder for dumping raw pixel (PPU framebuffer) to disk for debugging/testing.
class PngWriter
  def self.write(path, pixels, width:, height:, palette:)
    # Image data: raw RGB pixels, no filter, no interlacing
    raw = +''.b
    height.times do |y|
      raw << "\x00".b # filter type: None
      width.times { |x| raw << palette[pixels[(y * width) + x]].pack('C3') }
    end

    idat = Zlib::Deflate.deflate(raw)

    File.open(path, 'wb') do |f|
      f.write("\x89PNG\r\n\x1A\n".b)

      # Image header (width, height, bitdepth, colortype, compression, filter, interlace)
      f.write(chunk('IHDR', [width, height, 8, 2, 0, 0, 0].pack('N2C5')))

      f.write(chunk('IDAT', idat))
      f.write(chunk('IEND', ''.b))
    end
  end

  def self.chunk(type, data)
    [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
  end

  private_class_method :chunk
end

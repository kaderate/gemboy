# frozen_string_literal: true

# BatteryRAM is a class that represents the battery-backed RAM of a Gameboy.
# The format doesn't really matter, but load and save must be fully commutative.
class BatteryRAM
  DATE_SPECIFIER = { 48 => { size: 8, format: 'Q<' }, 44 => { size: 4, format: 'V' } }.freeze
  DEFAULT_DATE_SPECIFIER = DATE_SPECIFIER[48]
  VALID_BATTERY_RAM_SIZES = DATE_SPECIFIER.keys.freeze

  BatteryRAMConfig = Struct.new(
    :saved_ram,
    :battery_ram_path,
    :rtc_registers,
    :rtc_latched_registers,
    :rtc_unix_timestamp,
    keyword_init: true
  ) do
    def rtc_config = { rtc_registers:, rtc_latched_registers:, rtc_unix_timestamp: }
  end

  class CorruptedBatteryRAMError < StandardError; end

  def self.load(path, ram_size:)
    raw_content = File.binread(path) if File.exist?(path)

    # An empty .sav file must be considered as no RAM to allow it to be properly initialized.
    return BatteryRAMConfig.new(saved_ram: nil, battery_ram_path: path) if raw_content.nil? || raw_content.empty?

    saved_ram = raw_content.byteslice(0, ram_size).bytes
    rtc_args = read_rtc_registers(path, raw_content, ram_size)

    BatteryRAMConfig.new(saved_ram:, battery_ram_path: path, **rtc_args)
  end

  def self.save(path, data, rtc_registers: nil, rtc_latched_registers: nil)
    raise ArgumentError, 'pass both rtc registers arg or none' if rtc_registers.nil? ^ rtc_latched_registers.nil?

    file_content = data.pack('C*')
    file_content += rtc_registers.pack('V5') if rtc_registers
    file_content += rtc_latched_registers.pack('V5') if rtc_latched_registers
    file_content += [Time.now.to_i].pack(DEFAULT_DATE_SPECIFIER[:format]) if rtc_registers || rtc_latched_registers
    File.binwrite(path, file_content)
  end

  def self.read_rtc_registers(path, raw_content, ram_size)
    trailer_size = raw_content.bytesize - ram_size
    return {} if trailer_size.zero?

    raise_truncated!(path, raw_content, ram_size) if trailer_size.negative?
    return warn_unknown_trailer(path, trailer_size) unless VALID_BATTERY_RAM_SIZES.include?(trailer_size)

    rtc_offset = ram_size
    rtc_registers = raw_content.byteslice(rtc_offset, 5 * 4).unpack('V5')

    rtc_offset += 5 * 4
    rtc_latched_registers = raw_content.byteslice(rtc_offset, 5 * 4).unpack('V5')

    rtc_offset += 5 * 4
    date_specifier = DATE_SPECIFIER[trailer_size]
    rtc_unix_timestamp = raw_content.byteslice(rtc_offset, date_specifier[:size]).unpack1(date_specifier[:format])

    { rtc_registers:, rtc_latched_registers:, rtc_unix_timestamp: }
  end

  # Booting anyway with a shorter file would show the game an empty save, and its first write would overwrite what is left.
  def self.raise_truncated!(path, raw_content, ram_size)
    raise CorruptedBatteryRAMError,
          format('Truncated battery RAM in %<path>s: expected at least %<ram_size>d bytes, got %<size>d',
                 path:, ram_size:, size: raw_content.bytesize)
  end

  def self.warn_unknown_trailer(path, trailer_size)
    warn format('Ignoring %<trailer_size>d trailing bytes in %<path>s (game data is intact, ' \
                'the next save will rewrite the file cleanly)', trailer_size:, path:)
    {}
  end

  private_class_method :read_rtc_registers, :raise_truncated!, :warn_unknown_trailer
end

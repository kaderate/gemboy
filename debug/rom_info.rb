# frozen_string_literal: true

# Lists the cartridge header of every ROM in a directory, and whether this
# emulator supports its mapper.
#
# Usage: ruby debug/rom_info.rb [dir]

require_relative '../lib/rom_loader'

DIR = ARGV[0] || 'roms'
SUPPORTED_MBC = [0, 1, 3, 5].freeze
CART_TYPE_OFFSET = 0x0147
HEADERS = ['FILE', 'NAME', 'TYPE', 'BANKS', 'RAM', 'SAV?', ''].freeze

def rom_info(path)
  loader = RomLoader.new(path)
  {
    file: File.basename(path),
    name: loader.name.gsub(/[^[:print:]]/, '').strip,
    type: format('%<summary>s (0x%<byte>02X)',
                 summary: loader.cart_type_summary, byte: loader.rom_bytes[CART_TYPE_OFFSET]),
    banks: loader.rom_bank_count.to_s,
    ram: loader.ram_size.zero? ? '-' : "#{loader.ram_size / 1024}K",
    sav: File.exist?(Pathname.new(path).sub_ext('.sav').to_s) ? 'yes' : 'no',
    ok: SUPPORTED_MBC.include?(loader.mbc) ? 'ok' : "MBC#{loader.mbc} unsupported"
  }
rescue StandardError => e
  byte = File.binread(path, 1, CART_TYPE_OFFSET)&.unpack1('C')
  { file: File.basename(path), name: '?', type: format('unknown (0x%<byte>02X)', byte:),
    banks: '?', ram: '?', sav: '?', ok: e.class.to_s }
end

paths = Dir.glob(File.join(DIR, '**', '*.{gb,gbc}'))
abort "No ROM found in #{DIR}" if paths.empty?

rows = paths.map { |path| rom_info(path) }
widths = HEADERS.each_with_index.map do |header, i|
  key = %i[file name type banks ram sav ok][i]
  [header.length, *rows.map { |row| row[key].length }].max
end

line = ->(cells) { puts cells.each_with_index.map { |cell, i| cell.ljust(widths[i]) }.join('  ').rstrip }

line.call(HEADERS)
line.call(widths.map { |w| '-' * w })
rows.each { |row| line.call(row.values_at(:file, :name, :type, :banks, :ram, :sav, :ok)) }

unsupported = rows.count { |row| row[:ok] != 'ok' }
puts format("\n%<total>d ROMs, %<unsupported>d unsupported", total: rows.size, unsupported:)

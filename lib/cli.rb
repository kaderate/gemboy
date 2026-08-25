# frozen_string_literal: true

require 'rbconfig'

require_relative 'engine'
require_relative 'debug/server'

# CLI parses ARGV and builds an Engine
class CLI
  DEBUG_SERVER_FLAG = /\A--debug-server(?:=(\d+))?\z/

  def self.build_with_rom
    args = ARGV.dup
    debug_port = nil
    args.reject! do |arg|
      match = DEBUG_SERVER_FLAG.match(arg)
      next false unless match

      debug_port = (match[1] || Debug::DEFAULT_PORT).to_i
      true
    end

    usage_and_exit if args.size > 1

    rom_path = args.empty? ? rom_path_from_dialog : args[0].strip
    Engine.new(rom_path, debug_port:)
  end

  def self.rom_path_from_dialog
    usage_and_exit unless RbConfig::CONFIG['host_os'].match?(/darwin/)

    prompt = 'POSIX path of (choose file with prompt "ROM" of type {"gb","gbc"})'
    rom_path = `osascript -e '#{prompt}' 2>/dev/null`.strip
    exit(0) if rom_path.empty? # dialog cancelled

    puts "Selected ROM: #{rom_path}" # logger not yet initialized
    rom_path
  end

  def self.usage_and_exit
    puts "Usage: #{$PROGRAM_NAME} [--debug-server[=PORT]] <rom_path>"
    puts '  rom_path: path to a DMG/GBC ROM (optional on macOS, where a file picker opens)'
    puts "  --debug-server: serve the debug UI on 127.0.0.1 (default port #{Debug::DEFAULT_PORT})"
    exit(1)
  end
end

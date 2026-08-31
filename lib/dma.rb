# frozen_string_literal: true

require_relative 'edge_detector'

# GameBoy DMG-01 DMA management
# GDMA: General-purpose DMA (instant), HDMA: HBlank DMA (progressive)
class DMA
  VALID_SOURCE_RANGES = [0x0..0x7FF0, 0xA000..0xDFF0].freeze
  VALID_DESTINATION = 0x8000..0x9FF0
  REGISTERS_FROM_ADDR = {
    0xFF51 => :source_high,
    0xFF52 => :source_low,
    0xFF53 => :destination_high,
    0xFF54 => :destination_low,
    0xFF55 => :control # Bit 7: transfer mode, bits 0-6: transfer length
  }.freeze
  MAX_COUNTER = 0x7F

  attr_writer :mmu
  attr_reader :mode, :source, :destination, :transfer_active, :transfer_length, :transfer_rev_counter

  def initialize(mmu = nil)
    @mmu = mmu
    @mode = 0 # 0: GDMA, 1: HDMA
    @transfer_length = 0
    @source = 0
    @destination = 0

    @transfer_active = false
    @transfer_rev_counter = 0
  end

  def advance_hdma_transfer!
    transfer_one_step if @transfer_active
  end

  def read(addr)
    case REGISTERS_FROM_ADDR[addr]
    when :destination_low
      @destination & 0xF0
    when :destination_high
      (@destination >> 8) & 0xFF
    when :source_low
      @source & 0xF0
    when :source_high
      (@source >> 8) & 0xFF
    when :control
      if @transfer_active
        @transfer_rev_counter - 1
      else
        0xFF
      end
    else
      raise "DMA address #{addr} is invalid"
    end
  end

  def write(addr, value)
    case REGISTERS_FROM_ADDR[addr]
    when :destination_low
      @destination = (@destination & 0xFF00) | (value & 0xF0) # Ignore the 4 lower bits
    when :destination_high
      @destination = (@destination & 0x00FF) | (((value & 0x1F) | 0x80) << 8) # Force the 3 higher bits to 100
    when :source_low
      @source = (@source & 0xFF00) | (value & 0xF0) # Ignore the 4 lower bits
    when :source_high
      @source = (@source & 0x00FF) | (value << 8)
    when :control
      @mode = (value >> 7) & 1
      @transfer_length = value & MAX_COUNTER

      if @transfer_active && @mode == 0
        cancel_transfer!
      else
        start_transfer!
      end
    else
      raise "DMA address #{addr} is invalid"
    end
  end

  private

  def start_transfer!
    @transfer_active = true
    @transfer_rev_counter = @transfer_length + 1
    transfer_gdma! if gdma?
  end

  def cancel_transfer!
    @transfer_active = false
  end

  def transfer_gdma! = 128.times { transfer_one_step }

  def transfer_one_step
    if transfer_complete?
      @transfer_active = false
      return
    end

    16.times { transfer_one_byte }
    @transfer_rev_counter -= 1
  end

  def transfer_one_byte
    @mmu.write(@destination, @mmu.read(@source))
    @destination += 1
    @source += 1
  end

  def transfer_complete?
    @transfer_rev_counter <= 0 ||
      VALID_SOURCE_RANGES.none? { |range| range.cover?(@source) } ||
      !VALID_DESTINATION.cover?(@destination)
  end

  def gdma? = @mode == 0
  def hdma? = @mode == 1
end

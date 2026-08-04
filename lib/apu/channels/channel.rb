# frozen_string_literal: true

require_relative '../period_divider'
require_relative '../length_timer'
require_relative '../volume_envelope'

class APU
  # The base class of Channels
  class Channel
    attr_reader :apu, :channel_number

    def initialize(channel_number:, apu:, mmu:)
      @channel_number = channel_number
      @key_nrx0 = :"nr#{channel_number}0"
      @key_nrx1 = :"nr#{channel_number}1"
      @key_nrx2 = :"nr#{channel_number}2"
      @key_nrx3 = :"nr#{channel_number}3"
      @key_nrx4 = :"nr#{channel_number}4"
      @addr_nrx0 = REGISTERS[@key_nrx0]
      @addr_nrx1 = REGISTERS[@key_nrx1]
      @addr_nrx2 = REGISTERS[@key_nrx2]
      @addr_nrx3 = REGISTERS[@key_nrx3]
      @addr_nrx4 = REGISTERS[@key_nrx4]

      @has_sweep = channel_number == 1

      @apu = apu
      @mmu = mmu

      # Common internal state
      @enabled = false
      @dac_enabled = false
      @timer = 0
    end

    def generate_pcm_sample
      return 0 unless @enabled && @dac_enabled

      DAC.to_pcm_sample(generate_digital_sample)
    end

    protected

    def trigger!
      @dac_enabled = fetch_dac_enabled
      enable_channel! if @dac_enabled
    end

    def enable_channel!
      @enabled = true
      apu.enable_master_control_channel(channel_number)
    end

    def disable_channel!
      @enabled = false
      apu.disable_master_control_channel(channel_number)
    end
  end
end

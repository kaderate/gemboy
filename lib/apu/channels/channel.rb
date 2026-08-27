# frozen_string_literal: true

require_relative '../period_divider'
require_relative '../length_timer'
require_relative '../volume_envelope'

class APU
  # The base class of Channels
  class Channel
    attr_reader :apu, :channel_number, :register_prefix, :enabled, :dac_enabled, :timer, :length_timer

    def initialize(channel_number:, apu:)
      @channel_number = channel_number
      @register_prefix = "nr#{channel_number}"
      @key_nrx0 = :"#{@register_prefix}0"
      @key_nrx1 = :"#{@register_prefix}1"
      @key_nrx2 = :"#{@register_prefix}2"
      @key_nrx3 = :"#{@register_prefix}3"
      @key_nrx4 = :"#{@register_prefix}4"
      @addr_nrx0 = REGISTERS[@key_nrx0]
      @addr_nrx1 = REGISTERS[@key_nrx1]
      @addr_nrx2 = REGISTERS[@key_nrx2]
      @addr_nrx3 = REGISTERS[@key_nrx3]
      @addr_nrx4 = REGISTERS[@key_nrx4]

      @has_sweep = channel_number == 1

      @apu = apu

      # Common internal state
      @enabled = false
      @dac_enabled = false
      @timer = 0
    end

    def generate_pcm_sample
      return 0 unless @enabled && @dac_enabled

      DAC.to_pcm_sample(generate_digital_sample)
    end

    def on_read(_addr, read_value) = read_value
    def write_allowed?(_addr) = @apu.enabled
    def reset_state! = @registers_to_reset.each { |addr| @apu.load(addr, 0) }

    protected

    def trigger!
      enable_channel! if @dac_enabled
    end

    def enable_channel!
      @enabled = true
    end

    def disable_channel!
      @enabled = false
    end
  end
end

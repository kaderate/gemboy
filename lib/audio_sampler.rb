# frozen_string_literal: true

require_relative 'sdl_loader'

# Audio sampler periodically fetching samples from the APU and send them to the audio driver
class AudioSampler
  SOUND_SAMPLE_RATE_HZ = 44_100
  CHANNELS = 2
  BUFFER_SIZE = 10_240

  attr_reader :audio_queue, :audio_driver

  def initialize(audio_queue:, logger: nil)
    @logger = logger
    @audio_queue = audio_queue
    @audio_driver = SDL2AudioDriver.new(sample_rate: SOUND_SAMPLE_RATE_HZ, channels: CHANNELS)
    @buffer = nil
  end

  def start # rubocop:disable Metrics/MethodLength
    Thread.new do
      @logger&.info { 'Starting audio thread' }
      puts 'Starting audio thread'

      loop do
        @buffer ||= []
        @buffer << audio_queue.pop # until audio_queue.empty? || buffer.size >= BUFFER_SIZE

        if @buffer.size >= 441
          audio_driver.write(@buffer)
          @buffer.clear
        end
      rescue StandardError => e
        puts "Audio thread error: #{e.class}: #{e.message}"
        puts e.backtrace.first(3).join("\n")
      end
    end
  end

  # Dummy audio driver (no audio)
  class DummyAudioDriver
    def write(_buffer); end
  end

  # SDL2 audio driver
  class SDL2AudioDriver
    def initialize(sample_rate:, channels:, logger: nil)
      logger&.info { "Initializing SDL2 audio driver (sample rate: #{sample_rate}, channels: #{channels})" }
      puts "Initializing SDL2 audio driver (sample rate: #{sample_rate}, channels: #{channels})"

      SDL.Init(SDL::INIT_AUDIO)

      desired_audio_format = SDL::AudioSpec.new
      desired_audio_format[:freq]     = sample_rate
      desired_audio_format[:format]   = SDL::AUDIO_S16SYS
      desired_audio_format[:channels] = channels
      desired_audio_format[:samples]  = 512
      desired_audio_format[:callback] = nil

      obtained_audio_format = SDL::AudioSpec.new
      @audio_device = SDL.OpenAudioDevice(nil, 0, desired_audio_format, obtained_audio_format, 0)
      raise "SDL_OpenAudioDevice failed: #{SDL.GetError.read_string}" if @audio_device.zero?

      SDL.PauseAudioDevice(@audio_device, 0)
    end

    def write(buffer)
      pcm = buffer.flat_map do |sample|
        s16 = (sample * 32_767).clamp(-32_768, 32_767).to_i
        [s16, s16]
      end.pack('s*')

      # puts "> PCM: #{pcm.inspect} (buffer size: #{buffer.size})"

      res = SDL.QueueAudio(@audio_device, pcm, pcm.bytesize)
      puts "> QueueAudio Error: #{SDL.GetError.read_string}" if res == -1
    end
  end
end

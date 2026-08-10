# frozen_string_literal: true

require_relative '../../lib/utils/frame_limiter'

RSpec.describe FrameLimiter do
  let(:frame_duration) { described_class::TARGET_FRAME_DURATION_SEC }

  # Le temps est piloté via Process.clock_gettime, la seule horloge que la classe lit.
  # and_call_original en premier pour ne pas casser les appels des autres horloges.
  def set_clock(time)
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(time)
  end

  def build_limiter
    set_clock(0.0)
    described_class.new.tap { |limiter| allow(limiter).to receive(:sleep) }
  end

  describe '#frame_count' do
    it 'increments once per frame, monotonically' do
      limiter = build_limiter

      counts = (1..4).map do |frame|
        set_clock(frame * frame_duration)
        limiter.limit_frames_per_second!
        limiter.frame_count
      end

      expect(counts).to eq([1, 2, 3, 4])
    end
  end

  describe '#limit_frames_per_second!' do
    it 'sleeps exactly up to the frame deadline' do
      limiter = build_limiter

      set_clock(0.011) # 11 ms de travail sur une cible de ~16.75 ms
      limiter.limit_frames_per_second!

      expect(limiter).to have_received(:sleep).with(be_within(1e-6).of(frame_duration - 0.011))
    end

    it 'does not sleep when the deadline is already past' do
      limiter = build_limiter

      set_clock(2.5 * frame_duration) # une frame et demie de retard
      limiter.limit_frames_per_second!

      expect(limiter).not_to have_received(:sleep)
    end

    # Propriété centrale de l'échéance absolue : le sommeil vise base + n × durée,
    # donc un sleep qui déborde raccourcit d'autant le suivant au lieu de décaler
    # toute la suite. C'est ce qui distingue ce schéma d'un cadencement relatif.
    it 'shortens the next sleep by exactly the overshoot of the previous one' do
      limiter = build_limiter
      overshoot = 0.002
      slept = []
      allow(limiter).to receive(:sleep) { |duration| slept << duration }

      set_clock(0.011)
      limiter.limit_frames_per_second!

      set_clock(frame_duration + overshoot + 0.011) # le sleep a débordé de 2 ms, puis 11 ms de travail
      limiter.limit_frames_per_second!

      expect(slept.last).to be_within(1e-6).of(slept.first - overshoot)
    end

    # Sans cet abandon de dette, un hoquet se rembourse à raison de la seule marge
    # par frame : 500 ms mettraient ~87 frames à se résorber, en avance rapide visible.
    it 'writes off a debt larger than the skip threshold, down to under one frame' do
      limiter = build_limiter
      debt = 29.5 * frame_duration

      set_clock(frame_duration + debt) # l'échéance de la frame 1 est dépassée de `debt`
      limiter.limit_frames_per_second!

      expect(limiter.sleep_time).to be_negative
      expect(limiter.sleep_time.abs).to be < frame_duration
      expect(limiter).not_to have_received(:sleep)
    end

    it 'leaves a debt below the threshold alone, letting the loop catch up on its own' do
      limiter = build_limiter
      debt = 2 * frame_duration

      set_clock(frame_duration + debt)
      limiter.limit_frames_per_second!

      expect(limiter.sleep_time).to be_within(1e-9).of(-debt)
    end

    it 'returns to the target pace within a few frames after a long stall' do
      limiter = build_limiter
      work = 0.011
      slept = []
      allow(limiter).to receive(:sleep) { |duration| slept << duration }

      now = 0.0
      sleep_times = Array.new(6) do |frame|
        now += work
        now += 0.5 if frame == 2 # hoquet
        set_clock(now)
        before = slept.size
        limiter.limit_frames_per_second!
        now += slept.last if slept.size > before
        limiter.sleep_time
      end

      expect(sleep_times[2].abs).to be < frame_duration # la dette du hoquet est absorbée d'un coup
      expect(sleep_times.last).to be_within(1e-6).of(frame_duration - work) # régime nominal retrouvé
    end

    it 'holds the target pace over several frames despite a systematic overshoot' do
      limiter = build_limiter
      overshoot = 0.001
      work = 0.011
      frames = 10
      slept = []
      allow(limiter).to receive(:sleep) { |duration| slept << duration }

      now = 0.0
      frames.times do
        now += work
        set_clock(now)
        before = slept.size
        limiter.limit_frames_per_second!
        now += slept.last + overshoot if slept.size > before
      end

      # Un cadencement relatif finirait à frames × (durée + dépassement) ; ici le
      # dépassement est absorbé et on reste sur la grille des échéances.
      expect(now).to be_within(1e-4).of((frames * frame_duration) + overshoot)
      expect(slept.last).to be_within(1e-6).of(frame_duration - work - overshoot)
    end
  end
end

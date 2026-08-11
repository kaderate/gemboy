# frozen_string_literal: true

require_relative '../../lib/utils/speed_limiter'

RSpec.describe SpeedLimiter do
  let(:slice_duration) { described_class::SLICE_DURATION_SEC }
  let(:cycles_per_slice) { described_class::CYCLES_PER_SLICE }

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

  describe '#throttle!' do
    # Le cadencement est indexé sur le temps émulé, pas sur les frames produites :
    # une ROM qui éteint le LCD (écran de chargement) n'émet aucune frame mais
    # continue de consommer des cycles, et doit rester régulée.
    it 'acts only once a full slice of cycles has accumulated' do
      limiter = build_limiter
      chunk = 100
      steps_below_slice = cycles_per_slice / chunk

      steps_below_slice.times { limiter.throttle!(chunk) }
      expect(limiter.slice_count).to eq(0)

      limiter.throttle!(chunk)
      expect(limiter.slice_count).to eq(1)
    end

    it 'does nothing at all below the slice threshold' do
      limiter = build_limiter

      limiter.throttle!(cycles_per_slice - 1)

      expect(limiter.slice_count).to eq(0)
      expect(limiter.sleep_time).to be_nil
      expect(limiter).not_to have_received(:sleep)
    end

    it 'increments the slice count once per slice, monotonically' do
      limiter = build_limiter

      counts = (1..4).map do |slice|
        set_clock(slice * slice_duration)
        limiter.throttle!(cycles_per_slice)
        limiter.slice_count
      end

      expect(counts).to eq([1, 2, 3, 4])
    end

    it 'sleeps exactly up to the slice deadline' do
      limiter = build_limiter

      set_clock(0.010) # 10 ms de travail réel pour une tranche de ~16.74 ms
      limiter.throttle!(cycles_per_slice)

      expect(limiter).to have_received(:sleep).with(be_within(1e-6).of(slice_duration - 0.010))
    end

    it 'does not sleep when the deadline is already past' do
      limiter = build_limiter

      set_clock(2.5 * slice_duration) # une tranche et demie de retard
      limiter.throttle!(cycles_per_slice)

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

      set_clock(0.010)
      limiter.throttle!(cycles_per_slice)

      set_clock(slice_duration + overshoot + 0.010) # le sleep a débordé de 2 ms, puis 10 ms de travail
      limiter.throttle!(cycles_per_slice)

      expect(slept.last).to be_within(1e-6).of(slept.first - overshoot)
    end

    # Sans cet abandon de dette, un hoquet se rembourse à raison de la seule marge
    # par tranche, en avance rapide visible et audible.
    it 'writes off a debt larger than the skip threshold, down to under one slice' do
      limiter = build_limiter
      debt = 29.5 * slice_duration

      set_clock(slice_duration + debt) # l'échéance de la tranche 1 est dépassée de `debt`
      limiter.throttle!(cycles_per_slice)

      expect(limiter.sleep_time).to be_negative
      expect(limiter.sleep_time.abs).to be < slice_duration
      expect(limiter).not_to have_received(:sleep)
    end

    it 'leaves a debt below the threshold alone, letting the loop catch up on its own' do
      limiter = build_limiter
      debt = 2 * slice_duration

      set_clock(slice_duration + debt)
      limiter.throttle!(cycles_per_slice)

      expect(limiter.sleep_time).to be_within(1e-9).of(-debt)
    end

    it 'returns to the target pace within a few slices after a long stall' do
      limiter = build_limiter
      work = 0.010
      slept = []
      allow(limiter).to receive(:sleep) { |duration| slept << duration }

      now = 0.0
      sleep_times = Array.new(6) do |slice|
        now += work
        now += 0.5 if slice == 2 # hoquet
        set_clock(now)
        before = slept.size
        limiter.throttle!(cycles_per_slice)
        now += slept.last if slept.size > before
        limiter.sleep_time
      end

      expect(sleep_times[2].abs).to be < slice_duration # la dette du hoquet est absorbée d'un coup
      expect(sleep_times.last).to be_within(1e-6).of(slice_duration - work) # régime nominal retrouvé
    end

    it 'holds the target pace over several slices despite a systematic overshoot' do
      limiter = build_limiter
      overshoot = 0.001
      work = 0.010
      slices = 10
      slept = []
      allow(limiter).to receive(:sleep) { |duration| slept << duration }

      now = 0.0
      slices.times do
        now += work
        set_clock(now)
        before = slept.size
        limiter.throttle!(cycles_per_slice)
        now += slept.last + overshoot if slept.size > before
      end

      # Un cadencement relatif finirait à slices × (durée + dépassement) ; ici le
      # dépassement est absorbé et on reste sur la grille des échéances.
      expect(now).to be_within(1e-4).of((slices * slice_duration) + overshoot)
      expect(slept.last).to be_within(1e-6).of(slice_duration - work - overshoot)
    end
  end
end

# frozen_string_literal: true

require_relative '../../lib/utils/interval_timer'

RSpec.describe IntervalTimer do
  # Le temps est piloté via Process.clock_gettime, la seule horloge que la classe lit.
  # and_call_original en premier pour ne pas casser les appels des autres horloges.
  def set_clock(time)
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(time)
  end

  def build_timer(target_in_seconds: 1.0)
    set_clock(0.0)
    described_class.new(target_in_seconds:)
  end

  describe '#initialize' do
    it 'rejects a zero or negative interval' do
      set_clock(0.0)
      expect { described_class.new(target_in_seconds: 0) }.to raise_error(ArgumentError)
      expect { described_class.new(target_in_seconds: -1) }.to raise_error(ArgumentError)
    end
  end

  describe '#elapsed?' do
    it 'is false before the interval has been reached' do
      timer = build_timer

      set_clock(0.999)

      expect(timer.elapsed?).to be(false)
    end

    it 'is true once the interval is reached exactly' do
      timer = build_timer

      set_clock(1.0)

      expect(timer.elapsed?).to be(true)
    end

    # Régression : un reset inconditionnel repoussait la référence à chaque appel,
    # si bien qu'un appel par frame ne laissait jamais l'intervalle s'accumuler.
    it 'still fires when polled repeatedly below the interval' do
      timer = build_timer

      [0.2, 0.4, 0.6, 0.8].each do |time|
        set_clock(time)
        expect(timer.elapsed?).to be(false)
      end
      set_clock(1.0)

      expect(timer.elapsed?).to be(true)
    end

    it 'requires a full new interval before firing again' do
      timer = build_timer
      set_clock(1.0)
      timer.elapsed?

      set_clock(1.999)
      expect(timer.elapsed?).to be(false)

      set_clock(2.0)
      expect(timer.elapsed?).to be(true)
    end

    # Le reset avance @last_time de l'intervalle plutôt que de le recaler sur l'instant
    # courant : un déclenchement tardif ne décale pas la grille des suivants.
    it 'keeps firing on the original grid after a late poll' do
      timer = build_timer

      set_clock(1.6) # déclenchement tardif de 0.6 s
      expect(timer.elapsed?).to be(true)

      set_clock(2.0) # la grille reste à 2.0, pas à 2.6
      expect(timer.elapsed?).to be(true)
    end

    it 'reports a single elapsed interval even when several have passed unpolled' do
      timer = build_timer

      set_clock(3.0)

      expect(timer.elapsed?).to be(true)
      expect(timer.elapsed?).to be(true) # rattrape l'intervalle suivant
      expect(timer.elapsed?).to be(true) # puis le troisième
      expect(timer.elapsed?).to be(false) # à jour
    end
  end
end

# frozen_string_literal: true

# Porte périodique : répond true une seule fois par intervalle écoulé.
# Le reset avance @last_time de l'intervalle au lieu de le recaler sur l'instant
# courant, pour que les déclenchements restent sur une grille fixe sans dériver.
class IntervalTimer
  def initialize(target_in_seconds:)
    raise ArgumentError, 'Target in seconds must be a positive number' unless target_in_seconds.positive?

    @target_in_seconds = target_in_seconds
    @last_time = fetch_now
  end

  def elapsed?
    (fetch_now - @last_time >= @target_in_seconds).tap { |elapsed| reset! if elapsed }
  end

  private

  def reset!
    @last_time += @target_in_seconds
  end

  def fetch_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

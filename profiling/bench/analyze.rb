# frozen_string_literal: true

# Summarizes bench_results.csv: median/IQR throughput (instructions/sec) per profile x mode,
# plus a permutation test on the median difference between yjit and zjit (nonparametric --
# safer than a t-test given the small N and the non-normal, scheduler-noise-skewed timings
# typical of wall-clock benchmarks).
#
# Usage: ruby analyze.rb [bench_results.csv]

path = ARGV[0] || 'bench_results.csv'
lines = File.readlines(path, chomp: true)
header = lines.shift.split(',')
rows = lines.map { |line| header.zip(line.split(',')).to_h }

def median(arr)
  sorted = arr.sort
  n = sorted.size
  mid = n / 2
  n.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
end

def percentile(arr, p)
  sorted = arr.sort
  idx = (p * (sorted.size - 1)).round
  sorted[idx]
end

# Two-sided permutation test on the difference of medians, no distributional assumption.
def permutation_p_value(a, b, iterations: 10_000)
  observed = (median(a) - median(b)).abs
  pooled = a + b
  na = a.size
  count = 0
  iterations.times do
    shuffled = pooled.shuffle
    perm_diff = (median(shuffled[0...na]) - median(shuffled[na..])).abs
    count += 1 if perm_diff >= observed
  end
  count.to_f / iterations
end

by_profile = rows.group_by { |r| r['profile'] }

by_profile.each do |profile, profile_rows|
  puts "== #{profile} =="

  throughput_by_mode = profile_rows.group_by { |r| r['mode'] }.transform_values do |mode_rows|
    mode_rows.map { |r| r['measured_steps'].to_f / r['elapsed_seconds'].to_f }
  end

  throughput_by_mode.each do |mode, throughputs|
    med = median(throughputs)
    p25 = percentile(throughputs, 0.25)
    p75 = percentile(throughputs, 0.75)
    printf("  %-6s n=%-3d median=%.0f instr/s  IQR=[%.0f, %.0f]\n", mode, throughputs.size, med, p25, p75)
  end

  next unless throughput_by_mode['yjit'] && throughput_by_mode['zjit']

  yjit_med = median(throughput_by_mode['yjit'])
  zjit_med = median(throughput_by_mode['zjit'])
  ratio = yjit_med / zjit_med
  p_value = permutation_p_value(throughput_by_mode['yjit'], throughput_by_mode['zjit'])
  printf("  yjit/zjit median ratio = %.3fx  (permutation p=%.4f)\n", ratio, p_value)
  puts
end

# frozen_string_literal: true

# usage: ruby profiling/read_profiling.rb [stackprof|vernier] [path] [rows]

type = ARGV[0] == 'stackprof' ? :stackprof : :vernier
path = ARGV[1]
rows = (ARGV[2] || 15).to_i

if type == :stackprof
  require 'stackprof'
  path ||= 'profiling/stackprof-report.dump'
  report = StackProf::Report.new(Marshal.load(File.read(path))) # rubocop:disable Security/MarshalLoad
  report.print_text(false, rows)
  exit
end

require 'json'

# Vernier::Output::Top only reports the main thread, which on a live capture is the SDL loop
# blocking on vsync -- the emulation thread it hides is the whole point of the profile.
def self_time(thread)
  strings = thread['stringArray']
  func_name = thread['funcTable']['name']
  frame_func = thread['frameTable']['func']
  stack_frame = thread['stackTable']['frame']
  samples = thread['samples']
  weights = samples['weight'] || Array.new(samples['stack'].size, 1)

  totals = Hash.new(0)
  samples['stack'].each_with_index do |stack, index|
    next unless stack

    totals[strings[func_name[frame_func[stack_frame[stack]]]]] += weights[index] || 1
  end
  totals
end

path ||= 'profiling/vernier-report.json'
JSON.parse(File.read(path))['threads'].each do |thread|
  totals = self_time(thread)
  total = totals.values.sum
  next if total.zero?

  puts "\n== #{thread['name']}#{' (main)' if thread['isMainThread']} — #{total} samples"
  totals.sort_by { |_, weight| -weight }.first(rows).each do |name, weight|
    puts format('  %<weight>7d  %<share>5.1f%%  %<name>s', weight:, share: weight * 100.0 / total, name:)
  end
end

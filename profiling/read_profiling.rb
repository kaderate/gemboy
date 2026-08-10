# frozen_string_literal: true

# usage: ruby profiling/read_profiling.rb [stackprof|vernier] [path]

type = ARGV[0] == 'stackprof' ? :stackprof : :vernier
path = ARGV[1]

if type == :stackprof
  require 'stackprof'
  path ||= 'profiling/stackprof-report.dump'
  report = StackProf::Report.new(Marshal.load(File.read(path))) # rubocop:disable Security/MarshalLoad
  report.print_text(false, 25)
else
  require 'vernier'
  path ||= 'profiling/vernier-report.json'
  result = Vernier::ParsedProfile.read_file(path)
  puts Vernier::Output::Top.new(result, 25).output
end

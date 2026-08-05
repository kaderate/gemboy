require 'stackprof'

report = StackProf::Report.new(Marshal.load(File.read('profiling/stackprof-report.dump'))) # rubocop:disable Security/MarshalLoad
report.print_text(false, 25)

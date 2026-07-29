require 'stackprof'

report = StackProf::Report.new(Marshal.load(File.read('profiling/stackprof-report.dump')))
report.print_text(false, 25)

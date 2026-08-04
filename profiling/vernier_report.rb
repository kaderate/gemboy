require 'vernier'

path = ARGV[0] || 'profiling/vernier-report.json'
result = Vernier::ParsedProfile.read_file(path)
puts Vernier::Output::Top.new(result, 25).output

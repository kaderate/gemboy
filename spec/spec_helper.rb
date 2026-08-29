# frozen_string_literal: true

# The accuracy run drives whole ROMs: SimpleCov cancels YJIT there (33s -> 3min) and its partial
# report would overwrite the real one.
unless ARGV.any? { |arg| arg.include?('accuracy') }
  require 'simplecov'
  SimpleCov.start do
    skip '/spec/'
  end
end

Dir[File.expand_path('support/**/*.rb', __dir__)].each { require _1 }

RSpec.configure do |config|
  config.include Builders

  # Reference ROMs take ~40s: opt in with `rspec --tag accuracy`, as CI does.
  config.filter_run_excluding(:accuracy)
end

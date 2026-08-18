# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  skip '/spec/'
end

Dir[File.expand_path('support/**/*.rb', __dir__)].each { require _1 }

RSpec.configure do |config|
  config.include Builders
end

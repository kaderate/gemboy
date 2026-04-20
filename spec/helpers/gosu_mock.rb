RSpec.configure do |config|
  config.before(:suite) do
    module Gosu
      MOCK_KEYS = {
        KB_UP: 'up', KB_DOWN: 'down', KB_LEFT: 'left', KB_RIGHT: 'right',
        KB_A: 'a', KB_B: 'b', KB_RETURN: 'start', KB_SPACE: 'select'
      }.freeze

      old_verbose = $VERBOSE
      $VERBOSE = nil
      MOCK_KEYS.each { |name, val| const_set(name, val) }
      $VERBOSE = old_verbose
    end
  end
end

# Counts the number of frames per second in a loop
class FPSCounter
  attr_reader :count, :last_time, :last_fps

  def initialize(sleep_time: nil)
    @count = 0
    @last_time = Time.now
    @sleep_time = sleep_time
    @last_fps = 0
  end

  def update
    @count += 1
    Time.now.tap do |now|
      unless now - @last_time >= 1
        sleep!
        next
      end

      yield @count, @last_time if block_given?
      @last_time = now
      @last_fps = @count
      @count = 0
    end
  end

  def sleep!
    sleep @sleep_time if @sleep_time
  end
end



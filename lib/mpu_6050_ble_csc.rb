require "mpu_6050"
require "mpu_6050/rotation_detector"
require "ble_csc_service"

class MPU6050BLECSC
  def initialize(mpu, ble, name = "PicoRuby CSC", wheel_axis = :z, crank_axis = :x,
                 wheel_min_ms = 120, crank_min_ms = 250, notify_interval_ms = 1000,
                 sensor_location = nil, wheel_direction = 1, crank_direction = 1)
    @mpu = mpu
    @transport = ble
    @name = name
    @wheel_axis = wheel_axis
    @crank_axis = crank_axis
    @wheel_min_ms = wheel_min_ms
    @crank_min_ms = crank_min_ms
    @notify_interval_ms = notify_interval_ms
    @sensor_location = sensor_location
    @wheel_direction = wheel_direction
    @crank_direction = crank_direction
    @started = false
    @time_ms = 0
    @last_sample = nil
  end

  def mpu
    @mpu
  end

  def service
    @service
  end

  def wheel_detector
    @wheel_detector
  end

  def crank_detector
    @crank_detector
  end

  def last_sample
    @last_sample
  end

  def start
    @wheel_detector = @wheel_axis ? @mpu.rotation_detector(@wheel_axis, @wheel_min_ms, @wheel_direction) : nil
    @crank_detector = @crank_axis ? @mpu.rotation_detector(@crank_axis, @crank_min_ms, @crank_direction) : nil
    @service = BLECSCService.new(
      @transport,
      @name,
      !@wheel_detector.nil?,
      !@crank_detector.nil?,
      @sensor_location,
      @notify_interval_ms
    )
    @service.start
    @started = true
    true
  end

  def started?
    @started
  end

  def connected?
    @transport.connected?
  end

  def tick(time_ms = nil)
    start unless @started
    time_ms = @time_ms + 20 if time_ms.nil?
    @time_ms = time_ms
    event_seen = false
    @last_sample = @mpu.sample(time_ms)

    if @wheel_detector
      event = @wheel_detector.update(@last_sample)
      if event
        @service.update_wheel(event.count, event.time_ms)
        event_seen = true
      end
    end

    if @crank_detector
      event = @crank_detector.update(@last_sample)
      if event
        @service.update_crank(event.count, event.time_ms)
        event_seen = true
      end
    end

    if event_seen
      @service.notify(time_ms)
    else
      @service.notify_if_due(time_ms)
    end

    true
  end
end

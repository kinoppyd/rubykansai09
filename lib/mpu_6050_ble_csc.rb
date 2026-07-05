# Usage:
#   require "ble_transport/picoruby_peripheral"
#   require "mpu_6050_ble_csc"
#   i2c = I2C.new(unit: :RP2040_I2C0, frequency: 400_000, sda_pin: 4, scl_pin: 5)
#   mpu = MPU6050.new(i2c, :gyro_range_dps => 500, :sample_interval_ms => 10)
#   ble = BLETransport::PicoRubyPeripheral.new
#   sensor = MPU6050BLECSC.new(mpu, ble, "PicoRuby CSC", nil, :x)
#   sensor.start
#   loop do
#     sensor.tick
#     ble.poll
#   end
#
# Connects MPU6050 rotation events to the BLE Cycling Speed and Cadence
# service. Pass nil for wheel_axis or crank_axis to disable that channel.

require "mpu_6050"
require "mpu_6050/rotation_detector"
require "ble_csc_service"

class MPU6050BLECSC
  def initialize(mpu, ble, name = "PicoRuby CSC", wheel_axis = nil, crank_axis = :x,
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
    @last_sample = nil
    @last_wheel_count = 0
    @last_crank_count = 0
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
    if time_ms.nil?
      @last_sample = @mpu.sample_now
      time_ms = @last_sample.time_ms
    else
      @last_sample = @mpu.sample(time_ms)
    end

    if @wheel_detector
      event = @wheel_detector.update(@last_sample)
      if event
        delta = event.count - @last_wheel_count
        @last_wheel_count = event.count
        @service.add_wheel(delta, event.time_ms)
      end
    end

    if @crank_detector
      event = @crank_detector.update(@last_sample)
      if event
        delta = event.count - @last_crank_count
        @last_crank_count = event.count
        @service.add_crank(delta, event.time_ms)
      end
    end

    @service.notify_if_due(time_ms)

    true
  end
end

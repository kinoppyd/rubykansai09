require "mpu_6050"
require "ble_csc_service"

class MPU6050BLECSC
  DEFAULT_WHEEL = {
    :axis => :z,
    :direction => :positive,
    :alpha => 0.98,
    :min_period_ms => 120,
    :max_period_ms => 5_000,
    :gyro_deadband_dps => 1.0
  }

  DEFAULT_CRANK = {
    :axis => :x,
    :direction => :positive,
    :alpha => 0.95,
    :min_period_ms => 250,
    :max_period_ms => 3_000,
    :gyro_deadband_dps => 1.0
  }

  attr_reader :mpu, :service, :wheel_detector, :crank_detector
  attr_reader :last_sample, :last_error

  def initialize(mpu:, ble:, name: "PicoRuby CSC",
                 wheel: DEFAULT_WHEEL, crank: DEFAULT_CRANK,
                 notify_interval_ms: 1_000,
                 immediate_notify: true,
                 sensor_location: nil,
                 battery_level: nil,
                 manufacturer_name: "PicoRuby",
                 model_number: "MPU-6050 CSC",
                 firmware_revision: nil)
    @mpu = mpu
    @transport = ble
    @name = name
    @wheel_options = normalize_detector_options(wheel, DEFAULT_WHEEL)
    @crank_options = normalize_detector_options(crank, DEFAULT_CRANK)
    @notify_interval_ms = notify_interval_ms
    @immediate_notify = !!immediate_notify
    @sensor_location = sensor_location
    @battery_level = battery_level
    @manufacturer_name = manufacturer_name
    @model_number = model_number
    @firmware_revision = firmware_revision
    @started = false
    @last_sample = nil
    @last_error = nil
  end

  def start
    @wheel_detector = build_detector(@wheel_options)
    @crank_detector = build_detector(@crank_options)
    @service = BLECSCService.new(
      :transport => @transport,
      :name => @name,
      :wheel => !@wheel_detector.nil?,
      :crank => !@crank_detector.nil?,
      :notify_interval_ms => @notify_interval_ms,
      :sensor_location => @sensor_location,
      :battery_level => @battery_level,
      :manufacturer_name => @manufacturer_name,
      :model_number => @model_number,
      :firmware_revision => @firmware_revision
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
    raise "MPU6050BLECSC is not started" unless @started

    time_ms = now_ms if time_ms.nil?
    event_seen = false
    @last_sample = @mpu.sample(time_ms)

    if @wheel_detector
      if (event = @wheel_detector.update(@last_sample))
        @service.update_wheel(event.count, event.time_ms)
        event_seen = true
      end
    end

    if @crank_detector
      if (event = @crank_detector.update(@last_sample))
        @service.update_crank(event.count, event.time_ms)
        event_seen = true
      end
    end

    if event_seen && @immediate_notify
      @service.notify(time_ms)
    else
      @service.notify_if_due(time_ms)
    end

    @last_error = nil
    true
  rescue => e
    @last_error = e
    false
  end

  def run(delay_ms = 20)
    start unless started?
    loop do
      tick
      sleep_ms(delay_ms)
    end
  end

  private

  def normalize_detector_options(options, defaults)
    return nil if options == false || options.nil?
    merged = {}
    defaults.each { |key, value| merged[key] = value }
    options.each { |key, value| merged[key.to_sym] = value } if options.respond_to?(:each)
    merged
  end

  def build_detector(options)
    return nil if options.nil?
    axis = options[:axis]
    detector_options = {}
    options.each do |key, value|
      next if key == :axis
      detector_options[key] = value
    end
    @mpu.rotation_detector(axis, detector_options)
  end

  def now_ms
    if defined?(Machine) && Machine.respond_to?(:millis)
      Machine.millis
    elsif defined?(Time)
      (Time.now.to_f * 1000.0).to_i
    else
      0
    end
  end

  def sleep_ms(ms)
    if defined?(Machine) && Machine.respond_to?(:delay_ms)
      Machine.delay_ms(ms)
    elsif defined?(Kernel) && Kernel.respond_to?(:sleep)
      Kernel.sleep(ms.to_f / 1000.0)
    end
  end
end

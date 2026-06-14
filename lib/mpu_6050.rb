# MPU-6050 driver and rotation detector for PicoRuby/mruby.
#
# The driver expects an I2C object and accepts common method shapes:
# - readfrom_mem(addr, reg, len) / writeto_mem(addr, reg, data)
# - read_mem(addr, reg, len) / write_mem(addr, reg, data)
# - write_read(addr, data, len)
# - write(addr, data) + read(addr, len)
#
# RotationDetector estimates a continuous phase around one IMU axis with a
# complementary filter. Mount the sensor so the chosen axis is close to the
# wheel/crank rotation axis, then count each 2*pi phase crossing as one turn.
#
# == Usage
#
# Create and configure the driver with a PicoRuby I2C object:
#
#   require "mpu_6050"
#
#   mpu = MPU6050.new(
#     i2c,
#     :address => 0x68,
#     :accel_range_g => 2,
#     :gyro_range_dps => 500
#   )
#
# Keep the bicycle still while calibrating the gyro offset:
#
#   mpu.calibrate_gyro(200, 5)
#
# Read one fused sample:
#
#   sample = mpu.sample
#   puts sample.accel.x
#   puts sample.gyro.z
#   puts sample.roll
#
# Detect wheel and crank rotations. Choose the axis that is closest to the
# physical rotation axis of the mounted MPU-6050.
#
#   wheel = mpu.rotation_detector(
#     :z,
#     :alpha => 0.98,
#     :min_period_ms => 120,
#     :max_period_ms => 5000
#   )
#
#   crank = mpu.rotation_detector(
#     :x,
#     :alpha => 0.95,
#     :min_period_ms => 250,
#     :max_period_ms => 3000
#   )
#
#   loop do
#     sample = mpu.sample
#
#     if event = wheel.update(sample)
#       puts "wheel count=#{event.count} rpm=#{event.rpm}"
#     end
#
#     if event = crank.update(sample)
#       puts "crank count=#{event.count} rpm=#{event.rpm}"
#     end
#   end
#
# Use +event.count+ as the cumulative revolution counter and +event.time_ms+
# as the event timestamp when building BLE CSCS or ANT+ speed/cadence payloads.

class MPU6050
  DEFAULT_ADDRESS = 0x68

  REG_SMPLRT_DIV = 0x19
  REG_CONFIG = 0x1A
  REG_GYRO_CONFIG = 0x1B
  REG_ACCEL_CONFIG = 0x1C
  REG_ACCEL_XOUT_H = 0x3B
  REG_PWR_MGMT_1 = 0x6B
  REG_WHO_AM_I = 0x75

  ACCEL_SCALE = {
    2 => 16_384.0,
    4 => 8_192.0,
    8 => 4_096.0,
    16 => 2_048.0
  }

  GYRO_SCALE = {
    250 => 131.0,
    500 => 65.5,
    1000 => 32.8,
    2000 => 16.4
  }

  DEG_TO_RAD = Math::PI / 180.0
  RAD_TO_DEG = 180.0 / Math::PI

  class Vector3
    attr_accessor :x, :y, :z

    def initialize(x = 0.0, y = 0.0, z = 0.0)
      @x = x
      @y = y
      @z = z
    end

    def -(other)
      Vector3.new(@x - other.x, @y - other.y, @z - other.z)
    end

    def to_h
      { :x => @x, :y => @y, :z => @z }
    end
  end

  class Sample
    attr_reader :time_ms, :dt
    attr_reader :accel, :gyro, :temperature_c
    attr_reader :roll, :pitch, :yaw
    attr_reader :raw_accel, :raw_gyro, :raw_temperature

    def initialize(values)
      @time_ms = values[:time_ms]
      @dt = values[:dt]
      @accel = values[:accel]
      @gyro = values[:gyro]
      @temperature_c = values[:temperature_c]
      @roll = values[:roll]
      @pitch = values[:pitch]
      @yaw = values[:yaw]
      @raw_accel = values[:raw_accel]
      @raw_gyro = values[:raw_gyro]
      @raw_temperature = values[:raw_temperature]
    end
  end

  class RotationEvent
    attr_reader :time_ms, :count, :direction, :period_ms, :rpm, :phase

    def initialize(time_ms, count, direction, period_ms, rpm, phase)
      @time_ms = time_ms
      @count = count
      @direction = direction
      @period_ms = period_ms
      @rpm = rpm
      @phase = phase
    end
  end

  class OrientationFilter
    attr_reader :roll_rad, :pitch_rad, :yaw_rad

    def initialize(alpha = 0.98)
      @alpha = alpha
      @roll_rad = 0.0
      @pitch_rad = 0.0
      @yaw_rad = 0.0
      @initialized = false
    end

    def reset
      @roll_rad = 0.0
      @pitch_rad = 0.0
      @yaw_rad = 0.0
      @initialized = false
    end

    def update(accel, gyro, dt)
      accel_roll = Math.atan2(accel.y, accel.z)
      accel_pitch = Math.atan2(-accel.x, Math.sqrt(accel.y * accel.y + accel.z * accel.z))

      if !@initialized || dt <= 0.0
        @roll_rad = accel_roll
        @pitch_rad = accel_pitch
        @yaw_rad = 0.0
        @initialized = true
      else
        gyro_roll = @roll_rad + gyro.x * DEG_TO_RAD * dt
        gyro_pitch = @pitch_rad + gyro.y * DEG_TO_RAD * dt
        @yaw_rad = wrap_angle(@yaw_rad + gyro.z * DEG_TO_RAD * dt)

        @roll_rad = blend_angle(gyro_roll, accel_roll, @alpha)
        @pitch_rad = blend_angle(gyro_pitch, accel_pitch, @alpha)
      end

      {
        :roll => @roll_rad * RAD_TO_DEG,
        :pitch => @pitch_rad * RAD_TO_DEG,
        :yaw => @yaw_rad * RAD_TO_DEG
      }
    end

    private

    def blend_angle(predicted, measured, alpha)
      wrap_angle(predicted + (1.0 - alpha) * angle_delta(measured, predicted))
    end

    def angle_delta(target, current)
      wrap_angle(target - current)
    end

    def wrap_angle(angle)
      pi2 = Math::PI * 2.0
      while angle > Math::PI
        angle -= pi2
      end
      while angle < -Math::PI
        angle += pi2
      end
      angle
    end
  end

  class RotationDetector
    attr_reader :axis, :count, :rpm, :phase, :last_event

    def initialize(axis = :z, options = {})
      @axis = normalize_axis(axis)
      @alpha = option(options, :alpha, 0.98)
      @min_period_ms = option(options, :min_period_ms, 120)
      @max_period_ms = option(options, :max_period_ms, 5_000)
      @gyro_deadband_dps = option(options, :gyro_deadband_dps, 1.0)
      @direction = normalize_direction(option(options, :direction, :both))

      @count = 0
      @rpm = 0.0
      @phase = 0.0
      @continuous_phase = 0.0
      @last_count_phase = 0.0
      @last_time_ms = nil
      @last_event_time_ms = nil
      @last_event = nil
      @initialized = false
    end

    def reset
      @count = 0
      @rpm = 0.0
      @phase = 0.0
      @continuous_phase = 0.0
      @last_count_phase = 0.0
      @last_time_ms = nil
      @last_event_time_ms = nil
      @last_event = nil
      @initialized = false
    end

    def update(sample)
      time_ms = sample.time_ms
      dt = sample.dt
      dt = delta_time(time_ms) if dt.nil? || dt <= 0.0

      accel_phase = accel_phase_for(sample.accel)
      gyro_dps = gyro_for(sample.gyro)
      gyro_dps = 0.0 if gyro_dps.abs < @gyro_deadband_dps

      if !@initialized || dt <= 0.0
        @phase = accel_phase
        @continuous_phase = @phase
        @last_count_phase = @continuous_phase
        @last_time_ms = time_ms
        @initialized = true
        return nil
      end

      predicted = @phase + gyro_dps * DEG_TO_RAD * dt
      corrected = predicted + (1.0 - @alpha) * angle_delta(accel_phase, predicted)
      corrected = wrap_angle(corrected)

      step = angle_delta(corrected, @phase)
      @phase = corrected
      @continuous_phase += step
      @last_time_ms = time_ms

      event = detect_crossing(time_ms)
      update_timeout(time_ms)
      event
    end

    private

    def option(options, key, default_value)
      return default_value if options.nil?
      return options[key] if options.key?(key)
      string_key = key.to_s
      return options[string_key] if options.key?(string_key)
      default_value
    end

    def normalize_axis(axis)
      value = axis.to_sym
      return value if value == :x || value == :y || value == :z
      raise ArgumentError, "axis must be :x, :y, or :z"
    end

    def normalize_direction(direction)
      value = direction.to_sym
      return value if value == :positive || value == :negative || value == :both
      raise ArgumentError, "direction must be :positive, :negative, or :both"
    end

    def delta_time(time_ms)
      return 0.0 if @last_time_ms.nil? || time_ms.nil?
      (time_ms - @last_time_ms).to_f / 1000.0
    end

    def accel_phase_for(accel)
      case @axis
      when :x
        Math.atan2(accel.y, accel.z)
      when :y
        Math.atan2(accel.z, accel.x)
      else
        Math.atan2(accel.x, accel.y)
      end
    end

    def gyro_for(gyro)
      case @axis
      when :x
        gyro.x
      when :y
        gyro.y
      else
        gyro.z
      end
    end

    def detect_crossing(time_ms)
      pi2 = Math::PI * 2.0
      delta = @continuous_phase - @last_count_phase

      if delta >= pi2 && accepts_direction?(:positive)
        return accept_event(time_ms, :positive, pi2)
      elsif delta <= -pi2 && accepts_direction?(:negative)
        return accept_event(time_ms, :negative, -pi2)
      end

      nil
    end

    def accepts_direction?(direction)
      @direction == :both || @direction == direction
    end

    def accept_event(time_ms, direction, phase_step)
      period_ms = nil
      if !@last_event_time_ms.nil? && !time_ms.nil?
        period_ms = time_ms - @last_event_time_ms
        return nil if period_ms < @min_period_ms
      end

      @count += direction == :positive ? 1 : -1
      @last_count_phase += phase_step

      signed_rpm = 0.0
      if !period_ms.nil? && period_ms > 0
        signed_rpm = 60_000.0 / period_ms
        signed_rpm = -signed_rpm if direction == :negative
      end

      @rpm = signed_rpm
      @last_event_time_ms = time_ms
      @last_event = RotationEvent.new(time_ms, @count, direction, period_ms, @rpm, @continuous_phase)
      @last_event
    end

    def update_timeout(time_ms)
      return if @last_event_time_ms.nil? || time_ms.nil?
      @rpm = 0.0 if (time_ms - @last_event_time_ms) > @max_period_ms
    end

    def angle_delta(target, current)
      wrap_angle(target - current)
    end

    def wrap_angle(angle)
      pi2 = Math::PI * 2.0
      while angle > Math::PI
        angle -= pi2
      end
      while angle < -Math::PI
        angle += pi2
      end
      angle
    end
  end

  attr_reader :address, :accel_range_g, :gyro_range_dps
  attr_reader :gyro_offset, :orientation

  def initialize(i2c, options = {})
    @i2c = i2c
    @address = option(options, :address, DEFAULT_ADDRESS)
    @accel_range_g = option(options, :accel_range_g, 2)
    @gyro_range_dps = option(options, :gyro_range_dps, 250)
    @clock = option(options, :clock, nil)
    @auto_configure = option(options, :auto_configure, true)

    validate_scale!

    @accel_lsb_per_g = ACCEL_SCALE[@accel_range_g]
    @gyro_lsb_per_dps = GYRO_SCALE[@gyro_range_dps]
    @gyro_offset = Vector3.new
    @orientation = OrientationFilter.new(option(options, :filter_alpha, 0.98))
    @last_sample_time_ms = nil

    configure if @auto_configure
  end

  def configure(options = {})
    sample_rate_divider = option(options, :sample_rate_divider, 7)
    dlpf_config = option(options, :dlpf_config, 3)

    wake
    write_register(REG_SMPLRT_DIV, sample_rate_divider & 0xff)
    write_register(REG_CONFIG, dlpf_config & 0x07)
    write_register(REG_GYRO_CONFIG, gyro_config_value(@gyro_range_dps))
    write_register(REG_ACCEL_CONFIG, accel_config_value(@accel_range_g))
    true
  end

  def wake
    write_register(REG_PWR_MGMT_1, 0x01)
    true
  end

  def sleep
    write_register(REG_PWR_MGMT_1, 0x40)
    true
  end

  def who_am_i
    read_register(REG_WHO_AM_I, 1)[0]
  end

  def read_raw
    bytes = read_register(REG_ACCEL_XOUT_H, 14)
    {
      :accel => Vector3.new(
        int16(bytes[0], bytes[1]),
        int16(bytes[2], bytes[3]),
        int16(bytes[4], bytes[5])
      ),
      :temperature => int16(bytes[6], bytes[7]),
      :gyro => Vector3.new(
        int16(bytes[8], bytes[9]),
        int16(bytes[10], bytes[11]),
        int16(bytes[12], bytes[13])
      )
    }
  end

  def read
    raw = read_raw
    accel = Vector3.new(
      raw[:accel].x / @accel_lsb_per_g,
      raw[:accel].y / @accel_lsb_per_g,
      raw[:accel].z / @accel_lsb_per_g
    )
    gyro = Vector3.new(
      raw[:gyro].x / @gyro_lsb_per_dps - @gyro_offset.x,
      raw[:gyro].y / @gyro_lsb_per_dps - @gyro_offset.y,
      raw[:gyro].z / @gyro_lsb_per_dps - @gyro_offset.z
    )
    temperature_c = raw[:temperature] / 340.0 + 36.53

    {
      :accel => accel,
      :gyro => gyro,
      :temperature_c => temperature_c,
      :raw => raw
    }
  end

  def sample(time_ms = nil)
    time_ms = now_ms if time_ms.nil?
    dt = 0.0
    if !@last_sample_time_ms.nil? && !time_ms.nil?
      dt = (time_ms - @last_sample_time_ms).to_f / 1000.0
    end
    @last_sample_time_ms = time_ms

    data = read
    angles = @orientation.update(data[:accel], data[:gyro], dt)

    Sample.new(
      :time_ms => time_ms,
      :dt => dt,
      :accel => data[:accel],
      :gyro => data[:gyro],
      :temperature_c => data[:temperature_c],
      :roll => angles[:roll],
      :pitch => angles[:pitch],
      :yaw => angles[:yaw],
      :raw_accel => data[:raw][:accel],
      :raw_gyro => data[:raw][:gyro],
      :raw_temperature => data[:raw][:temperature]
    )
  end

  def calibrate_gyro(sample_count = 200, delay_ms = 5)
    sum = Vector3.new
    count = 0

    sample_count.times do
      raw = read_raw[:gyro]
      sum.x += raw.x / @gyro_lsb_per_dps
      sum.y += raw.y / @gyro_lsb_per_dps
      sum.z += raw.z / @gyro_lsb_per_dps
      count += 1
      delay(delay_ms) if delay_ms && delay_ms > 0
    end

    if count > 0
      @gyro_offset = Vector3.new(sum.x / count, sum.y / count, sum.z / count)
    end

    @gyro_offset
  end

  def reset_filter
    @orientation.reset
    @last_sample_time_ms = nil
  end

  def rotation_detector(axis = :z, options = {})
    RotationDetector.new(axis, options)
  end

  private

  def option(options, key, default_value)
    return default_value if options.nil?
    return options[key] if options.key?(key)
    string_key = key.to_s
    return options[string_key] if options.key?(string_key)
    default_value
  end

  def validate_scale!
    raise ArgumentError, "accel_range_g must be one of 2, 4, 8, 16" if ACCEL_SCALE[@accel_range_g].nil?
    raise ArgumentError, "gyro_range_dps must be one of 250, 500, 1000, 2000" if GYRO_SCALE[@gyro_range_dps].nil?
  end

  def accel_config_value(range)
    shift = { 2 => 0, 4 => 1, 8 => 2, 16 => 3 }[range]
    shift << 3
  end

  def gyro_config_value(range)
    shift = { 250 => 0, 500 => 1, 1000 => 2, 2000 => 3 }[range]
    shift << 3
  end

  def read_register(register, length)
    if @i2c.respond_to?(:readfrom_mem)
      return bytes_of(@i2c.readfrom_mem(@address, register, length))
    end

    if @i2c.respond_to?(:read_mem)
      return bytes_of(@i2c.read_mem(@address, register, length))
    end

    if @i2c.respond_to?(:write_read)
      return bytes_of(@i2c.write_read(@address, byte_string(register), length))
    end

    if @i2c.respond_to?(:write) && @i2c.respond_to?(:read)
      @i2c.write(@address, byte_string(register))
      return bytes_of(@i2c.read(@address, length))
    end

    raise "I2C object does not support register reads"
  end

  def write_register(register, value)
    data = byte_string(value)

    if @i2c.respond_to?(:writeto_mem)
      @i2c.writeto_mem(@address, register, data)
      return true
    end

    if @i2c.respond_to?(:write_mem)
      @i2c.write_mem(@address, register, data)
      return true
    end

    if @i2c.respond_to?(:write)
      @i2c.write(@address, byte_string(register, value))
      return true
    end

    raise "I2C object does not support register writes"
  end

  def byte_string(*values)
    string = ""
    string = string.force_encoding("BINARY") if string.respond_to?(:force_encoding)
    values.each do |value|
      string << (value & 0xff)
    end
    string
  end

  def bytes_of(data)
    if data.respond_to?(:bytes)
      data.bytes
    elsif data.respond_to?(:to_a)
      data.to_a
    else
      raise "I2C returned unsupported data type"
    end
  end

  def int16(high, low)
    value = ((high & 0xff) << 8) | (low & 0xff)
    value >= 0x8000 ? value - 0x10000 : value
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

  def delay(ms)
    if defined?(Machine) && Machine.respond_to?(:delay_ms)
      Machine.delay_ms(ms)
    elsif defined?(Kernel) && Kernel.respond_to?(:sleep)
      Kernel.sleep(ms.to_f / 1000.0)
    else
      nil
    end
  end
end

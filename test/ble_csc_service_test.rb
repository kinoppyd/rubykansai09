# Usage:
#   ruby -Ilib test/ble_csc_service_test.rb
#
# Exercises the public classes with CRuby and Minitest. PicoRuby smoke tests
# should use simple raise-based scripts instead of requiring Minitest.

require "minitest/autorun"
require "ble_transport/fake"
require "ble_csc_service"
require "mpu_6050_ble_csc"
require "mpu_6050/rotation_detector"

class BLECSCServiceTest < Minitest::Test
  def test_little_endian_helpers
    assert_equal [0x34, 0x12], BLETransport.u16_le(0x1234).bytes
    assert_equal [0xff, 0xff], BLETransport.s16_le(-1).bytes
    assert_equal [0x78, 0x56, 0x34, 0x12], BLETransport.u32_le(0x12345678).bytes
    assert_equal 0x1234, BLETransport.get_u16("\x34\x12", 0)
    assert_equal 0x12345678, BLETransport.get_u32("\x78\x56\x34\x12", 0)
  end

  def test_shared_csc_event_time_ticks
    assert_equal 0, BLETransport.csc_event_time_ticks(0)
    assert_equal 1_024, BLETransport.csc_event_time_ticks(1_000)
    assert_equal 0, BLETransport.csc_event_time_ticks(64_000)
  end

  def test_speed_only_payload
    transport = BLETransport::Fake.new
    service = BLECSCService.new(transport, "PicoRuby CSC", true, false)
    service.start
    service.update_wheel(3, 1_000)

    assert_equal [0x01, 3, 0, 0, 0, 0, 4], service.measurement_payload.bytes
  end

  def test_cadence_only_payload
    transport = BLETransport::Fake.new
    service = BLECSCService.new(transport, "PicoRuby CSC", false, true)
    service.start
    service.update_crank(7, 1_500)

    assert_equal [0x02, 7, 0, 0, 6], service.measurement_payload.bytes
  end

  def test_combined_payload_and_notification
    transport = BLETransport::Fake.new
    service = BLECSCService.new(transport)
    service.start
    service.update_wheel(3, 1_000)
    service.update_crank(7, 1_500)
    service.notify(1_500)

    assert_equal [0x03, 3, 0, 0, 0, 0, 4, 7, 0, 0, 6],
                 transport.notifications.last[:bytes].bytes
  end

  def test_native_transport_skips_ruby_measurement_payload
    transport = NativeTransport.new
    service = BLECSCService.new(transport, "PicoRuby CSC", false, true)
    service.start
    service.add_crank(3, 1_500)

    service.notify(1_500)

    assert_equal [0, 0, 3, 1_536], transport.csc_values
    assert_nil service.instance_variable_get(:@payload)
  end

  def test_notify_if_due
    transport = BLETransport::Fake.new
    service = BLECSCService.new(transport, "PicoRuby CSC", true, true, nil, 1_000)
    service.start

    assert_equal true, service.notify_if_due(0)
    assert_equal false, service.notify_if_due(999)
    assert_equal true, service.notify_if_due(1_000)
    assert_equal 2, transport.notifications.size
  end

  def test_notify_interval_handles_u32_clock_wrap
    transport = BLETransport::Fake.new
    service = BLECSCService.new(transport, "PicoRuby CSC", false, true, nil, 40)
    service.start

    assert_equal true, service.notify_if_due(0xfffffff0)
    assert_equal true, service.notify_if_due(0x18)
    assert_equal 2, transport.notifications.size
  end

  def test_wheel_counter_saturates_without_rollover
    service = BLECSCService.new(BLETransport::Fake.new, "PicoRuby CSC", true, false)

    service.update_wheel(0xffffffff, 0)
    service.add_wheel(1, 1_000)

    assert_equal 0xffffffff, service.wheel_revolutions
  end

  def test_crank_counter_rolls_over
    service = BLECSCService.new(BLETransport::Fake.new, "PicoRuby CSC", false, true)

    service.update_crank(0xffff, 0)
    service.add_crank(1, 1_000)

    assert_equal 0, service.crank_revolutions
  end

  def test_event_time_rolls_over_after_64_seconds
    assert_equal 0, BLECSCService.event_time_ticks(0)
    assert_equal 0, BLECSCService.event_time_ticks(64_000)
    assert_equal 1_024, BLECSCService.event_time_ticks(65_000)
  end

  def test_periodic_notification_does_not_change_last_event
    transport = BLETransport::Fake.new
    service = BLECSCService.new(transport, "PicoRuby CSC", false, true, nil, 1_000)
    service.start
    service.add_crank(1, 250)
    count = service.crank_revolutions
    event_time = service.crank_event_time

    service.notify_if_due(250)
    service.notify_if_due(1_250)

    assert_equal count, service.crank_revolutions
    assert_equal event_time, service.crank_event_time
    assert_equal transport.notifications[0][:bytes], transport.notifications[1][:bytes]
  end

  def test_mpu_6050_ble_csc_integration_counts_synthetic_rotation
    mpu = SyntheticMPU.new
    transport = BLETransport::Fake.new
    sensor = MPU6050BLECSC.new(
      mpu,
      transport,
      "PicoRuby CSC",
      :z,
      nil,
      1
    )
    sensor.start

    81.times do |i|
      sensor.tick(i * 100)
    end

    assert_equal 2, sensor.wheel_detector.count
    assert_equal 2, transport.notifications.last[:bytes].bytes[1]
  end

  def test_mpu_6050_ble_csc_uses_sample_now_when_time_is_omitted
    mpu = SyntheticNowMPU.new
    transport = BLETransport::Fake.new
    sensor = MPU6050BLECSC.new(mpu, transport, "PicoRuby CSC", :z, nil, 1)
    sensor.start

    81.times { sensor.tick }

    assert_equal 8_000, sensor.last_sample.time_ms
    assert_equal 2, sensor.service.wheel_revolutions
  end

  def test_mpu_6050_ble_csc_defaults_to_one_physical_cadence_sensor
    sensor = MPU6050BLECSC.new(SyntheticMPU.new, BLETransport::Fake.new)
    sensor.start

    assert_nil sensor.wheel_detector
    refute_nil sensor.crank_detector
    assert_equal BLECSCService::FEATURE_CRANK, sensor.service.feature_value
  end

  def test_rotation_detector_counts_gyro_rotation
    mpu = SyntheticGyroMPU.new
    detector = MPU6050::RotationDetector.new(:z, 120)

    22.times do |i|
      detector.update(mpu.sample(i * 100))
    end

    assert_equal 2, detector.count
  end

  def test_rotation_detector_exposes_debug_values
    mpu = SyntheticGyroMPU.new
    detector = MPU6050::RotationDetector.new(:z, 120)

    detector.update(mpu.sample(0))
    detector.update(mpu.sample(100))

    assert_in_delta 0.0, detector.phase, 0.0001
    assert_in_delta 0.6283, detector.delta_angle, 0.0001
    assert_in_delta 0.6283, detector.angle, 0.0001
    assert_equal 360.0, detector.gyro_dps
    assert_equal false, detector.saturated?
    assert_equal false, detector.dt_skipped?
    assert_equal true, detector.phase_valid?
  end

  def test_rotation_detector_skips_large_dt_samples
    mpu = SyntheticGyroMPU.new
    detector = MPU6050::RotationDetector.new(:z, 120, 0)
    detector.set_max_dt_ms(50)

    detector.update(mpu.sample(0))
    detector.update(mpu.sample(1_000))

    assert_equal 0, detector.count
    assert_equal true, detector.dt_skipped?
    assert_equal 0.0, detector.delta_angle
    assert_equal 0.0, detector.angle
  end

  def test_mpu_6050_defaults_to_wide_motion_ranges
    i2c = FakeI2C.new
    MPU6050.new(i2c)

    assert_equal [0x68, 0x1B, 24], i2c.writes[3]
    assert_equal [0x68, 0x1C, 24], i2c.writes[4]
  end

  def test_mpu_6050_sample_now_falls_back_to_configured_interval
    mpu = MPU6050.new(FakeI2C.new)

    mpu.sample_now
    assert_equal 0, mpu.time_ms
    mpu.sample_now
    assert_equal 10, mpu.time_ms
  end

  def test_mpu_6050_marks_saturated_acceleration
    mpu = MPU6050.new(SaturatingI2C.new)

    mpu.sample(0)

    assert_equal true, mpu.accel_saturated?
  end

  def test_mpu_6050_verifies_identity
    mpu = MPU6050.new(IdentityI2C.new)

    assert_equal true, mpu.verify_identity
  end

  def test_mpu_6050_rejects_wrong_identity
    mpu = MPU6050.new(FakeI2C.new)

    assert_raises(IOError) { mpu.verify_identity }
  end

  def test_mpu_6050_rejects_short_sample
    mpu = MPU6050.new(ShortI2C.new)

    assert_raises(IOError) { mpu.sample(0) }
  end

  def test_mpu_6050_marks_saturated_gyro
    mpu = MPU6050.new(GyroSaturatingI2C.new)

    mpu.sample(0)

    assert_equal true, mpu.gyro_saturated?
  end

  def test_mpu_6050_reuses_read_into_buffer
    i2c = ReusingI2C.new
    mpu = MPU6050.new(i2c)

    mpu.verify_identity
    mpu.sample(0)
    mpu.sample(10)

    assert_equal 1, i2c.sample_buffer_ids.uniq.size
  end

  def test_rotation_detector_ignores_saturated_accel_without_gyro
    mpu = SyntheticSaturatedMPU.new
    detector = MPU6050::RotationDetector.new(:z, 120)

    81.times do |i|
      detector.update(mpu.sample(i * 100))
    end

    assert_equal 0, detector.count
  end

  def test_rotation_detector_reports_saturation
    mpu = SyntheticSaturatedMPU.new
    detector = MPU6050::RotationDetector.new(:z, 120)

    detector.update(mpu.sample(0))

    assert_equal true, detector.saturated?
    assert_nil detector.phase
    assert_equal false, detector.phase_valid?
    assert_equal 0.0, detector.delta_angle
  end

  def test_rotation_detector_ignores_weak_accel_phase
    mpu = SyntheticWeakPhaseMPU.new
    detector = MPU6050::RotationDetector.new(:z, 120)

    81.times do |i|
      detector.update(mpu.sample(i * 100))
    end

    assert_equal 0, detector.count
    assert_equal false, detector.phase_valid?
  end

  def test_rotation_detector_does_not_integrate_clipped_gyro
    mpu = SyntheticGyroSaturatedMPU.new
    detector = MPU6050::RotationDetector.new(:z, 120)

    detector.update(mpu.sample(0))
    detector.update(mpu.sample(100))

    assert_equal true, detector.gyro_saturated?
    assert_equal true, detector.saturated?
    assert_equal 0.0, detector.delta_angle
    assert_equal 0.0, detector.angle
  end

  class FakeI2C
    attr_reader :writes

    def initialize
      @writes = []
    end

    def write(address, register, value)
      @writes << [address, register, value]
      true
    end

    def read(_address, length, _register)
      s = String.new
      while s.bytesize < length
        s << 0
      end
      s
    end
  end

  class NativeTransport
    attr_reader :csc_values

    def setup_csc(_name, _feature_payload, _sensor_location)
      1
    end

    def notify_csc(wheel_revolutions, wheel_time, crank_revolutions, crank_time)
      @csc_values = [wheel_revolutions, wheel_time, crank_revolutions, crank_time]
      true
    end

    def connected?
      true
    end
  end

  class SaturatingI2C < FakeI2C
    def read(_address, length, _register)
      s = String.new
      s << 0x7f
      s << 0xff
      while s.bytesize < length
        s << 0
      end
      s
    end
  end

  class IdentityI2C < FakeI2C
    def read(_address, length, register)
      return "\x68" if register == 0x75
      super
    end
  end

  class ShortI2C < FakeI2C
    def read(_address, _length, _register)
      "\x00"
    end
  end

  class GyroSaturatingI2C < FakeI2C
    def read(_address, length, _register)
      s = String.new
      while s.bytesize < length
        s << 0
      end
      s.setbyte(8, 0x7f) if length > 8
      s.setbyte(9, 0xff) if length > 9
      s
    end
  end

  class ReusingI2C < FakeI2C
    attr_reader :sample_buffer_ids

    def initialize
      super
      @sample_buffer_ids = []
    end

    def read_into(_address, buffer, register)
      i = 0
      while i < buffer.bytesize
        buffer.setbyte(i, 0)
        i += 1
      end
      buffer.setbyte(0, 0x68) if register == 0x75
      @sample_buffer_ids << buffer.object_id if register == 0x3B
      buffer
    end
  end

  class SyntheticGyroMPU
    def initialize
      @time_ms = nil
      @last_ms = nil
      @dt = 0.0
      @accel_x = 0.0
      @accel_y = 1.0
      @accel_z = 0.0
      @gyro_x = 0.0
      @gyro_y = 0.0
      @gyro_z = 360.0
    end

    attr_reader :time_ms, :dt
    attr_reader :accel_x, :accel_y, :accel_z
    attr_reader :gyro_x, :gyro_y, :gyro_z

    def sample(time_ms)
      @dt = @last_ms ? (time_ms - @last_ms).to_f / 1000.0 : 0.0
      @time_ms = time_ms
      @last_ms = time_ms
      self
    end
  end

  class SyntheticMPU
    def initialize
      @index = 0
      @time_ms = nil
      @dt = 0.1
      @accel_x = 0.0
      @accel_y = 1.0
      @accel_z = 0.0
      @gyro_x = 0.0
      @gyro_y = 0.0
      @gyro_z = 0.0
    end

    attr_reader :time_ms, :dt
    attr_reader :accel_x, :accel_y, :accel_z
    attr_reader :gyro_x, :gyro_y, :gyro_z

    def sample(time_ms)
      theta = 2.0 * Math::PI * @index / 40.0
      @index += 1
      @time_ms = time_ms
      @accel_x = Math.sin(theta)
      @accel_y = Math.cos(theta)
      self
    end

    def rotation_detector(axis, min_ms, direction = 0)
      MPU6050::RotationDetector.new(axis, min_ms, direction)
    end
  end

  class SyntheticNowMPU < SyntheticMPU
    def initialize
      super
      @now = -100
    end

    def sample_now
      @now += 100
      sample(@now)
    end
  end

  class SyntheticSaturatedMPU < SyntheticMPU
    def accel_saturated?
      true
    end
  end

  class SyntheticWeakPhaseMPU < SyntheticMPU
    def sample(time_ms)
      theta = 2.0 * Math::PI * @index / 40.0
      @index += 1
      @time_ms = time_ms
      @accel_x = Math.sin(theta) * 0.05
      @accel_y = Math.cos(theta) * 0.05
      @accel_z = -1.0
      self
    end
  end

  class SyntheticGyroSaturatedMPU < SyntheticGyroMPU
    def gyro_saturated?
      true
    end
  end
end

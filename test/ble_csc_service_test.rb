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

  def test_notify_if_due
    transport = BLETransport::Fake.new
    service = BLECSCService.new(transport, "PicoRuby CSC", true, true, nil, 1_000)
    service.start

    assert_equal true, service.notify_if_due(0)
    assert_equal false, service.notify_if_due(999)
    assert_equal true, service.notify_if_due(1_000)
    assert_equal 2, transport.notifications.size
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
end

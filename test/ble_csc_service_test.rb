require "minitest/autorun"
require "ble_csc_service"
require "mpu_6050_ble_csc"

class BLECSCServiceTest < Minitest::Test
  def test_little_endian_helpers
    assert_equal [0x34, 0x12], BLETransport::Bytes.u16_le(0x1234).bytes
    assert_equal [0xff, 0xff], BLETransport::Bytes.s16_le(-1).bytes
    assert_equal [0x78, 0x56, 0x34, 0x12], BLETransport::Bytes.u32_le(0x12345678).bytes
  end

  def test_speed_only_payload
    transport = BLETransport::Fake.new
    service = BLECSCService.new(:transport => transport, :wheel => true, :crank => false)
    service.start
    service.update_wheel(3, 1_000)

    assert_equal [0x01, 3, 0, 0, 0, 0, 4], service.measurement_payload.bytes
  end

  def test_cadence_only_payload
    transport = BLETransport::Fake.new
    service = BLECSCService.new(:transport => transport, :wheel => false, :crank => true)
    service.start
    service.update_crank(7, 1_500)

    assert_equal [0x02, 7, 0, 0, 6], service.measurement_payload.bytes
  end

  def test_combined_payload_and_notification
    transport = BLETransport::Fake.new
    service = BLECSCService.new(:transport => transport, :wheel => true, :crank => true)
    service.start
    service.update_wheel(3, 1_000)
    service.update_crank(7, 1_500)
    service.notify(1_500)

    assert_equal [0x03, 3, 0, 0, 0, 0, 4, 7, 0, 0, 6],
                 transport.notifications.last[:bytes].bytes
  end

  def test_notify_if_due
    transport = BLETransport::Fake.new
    service = BLECSCService.new(:transport => transport, :notify_interval_ms => 1_000)
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
      :mpu => mpu,
      :ble => transport,
      :wheel => { :axis => :z, :alpha => 0.0, :min_period_ms => 1 },
      :crank => false,
      :immediate_notify => true
    )
    sensor.start

    81.times do |i|
      sensor.tick(i * 100)
    end

    assert_equal 2, sensor.wheel_detector.count
    assert_equal 2, transport.notifications.last[:bytes].bytes[1]
  end

  class SyntheticMPU
    def initialize
      @index = 0
    end

    def sample(time_ms)
      theta = 2.0 * Math::PI * @index / 40.0
      @index += 1
      MPU6050::Sample.new(
        :time_ms => time_ms,
        :dt => 0.1,
        :accel => MPU6050::Vector3.new(Math.sin(theta), Math.cos(theta), 0.0),
        :gyro => MPU6050::Vector3.new(0.0, 0.0, 0.0),
        :temperature_c => 0.0,
        :roll => 0.0,
        :pitch => 0.0,
        :yaw => 0.0,
        :raw_accel => nil,
        :raw_gyro => nil,
        :raw_temperature => nil
      )
    end

    def rotation_detector(axis, options)
      MPU6050::RotationDetector.new(axis, options)
    end
  end
end

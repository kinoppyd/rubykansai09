# Usage:
#   ruby -Ilib test/ble_cycle_speed_estimator_test.rb

require "minitest/autorun"
require "ble_cycle_packet"
require "ble_cycle_host/speed_estimator"

class BLECycleSpeedEstimatorTest < Minitest::Test
  def test_update_calculates_speed_from_angle_delta
    packet = packet_with(3_142, 500)
    estimator = BLECycleHost::SpeedEstimator.new(2105)

    assert_equal true, estimator.update(packet)

    assert_in_delta 0.5, estimator.wheel_rotations, 0.001
    assert_in_delta 7.57, estimator.speed_kmh, 0.02
    assert_in_delta 60.0, estimator.cadence_rpm, 0.1
  end

  def test_update_uses_absolute_speed_for_reverse_rotation
    packet = packet_with(-3_142, 500)
    estimator = BLECycleHost::SpeedEstimator.new(2105)

    estimator.update(packet)

    assert_in_delta 7.57, estimator.speed_kmh, 0.02
    assert_in_delta 60.0, estimator.cadence_rpm, 0.1
  end

  def test_update_rejects_zero_interval
    packet = packet_with(3_142, 0)
    estimator = BLECycleHost::SpeedEstimator.new(2105)

    assert_equal false, estimator.update(packet)
    assert_equal 0.0, estimator.speed_kmh
    assert_equal 0.0, estimator.cadence_rpm
  end

  private

  def packet_with(delta_angle_mrad, interval_ms)
    payload = BLECyclePacket.bytes(BLECyclePacket::SIZE)
    BLECyclePacket.encode_into(
      payload,
      BLECyclePacket::FLAG_ANGLE_VALID,
      1,
      1_000,
      0,
      delta_angle_mrad,
      interval_ms,
      0
    )
    BLECyclePacket.decode(payload)
  end
end

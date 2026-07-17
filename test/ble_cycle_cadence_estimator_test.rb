# Usage:
#   ruby -Ilib test/ble_cycle_cadence_estimator_test.rb

require "minitest/autorun"
require "ble_cycle_packet"
require "ble_cycle_host/cadence_estimator"

class BLECycleCadenceEstimatorTest < Minitest::Test
  def test_update_calculates_sixty_rpm_from_one_rotation_per_second
    estimator = BLECycleHost::CadenceEstimator.new

    assert_equal true, estimator.update(packet_with(6_283, 1_000))

    assert_in_delta 60.0, estimator.cadence_rpm, 0.02
    refute_respond_to estimator, :speed_kmh
  end

  def test_update_calculates_same_rpm_from_half_rotation
    estimator = BLECycleHost::CadenceEstimator.new

    estimator.update(packet_with(3_142, 500))

    assert_in_delta 60.0, estimator.cadence_rpm, 0.1
  end

  def test_update_uses_absolute_value_for_reverse_rotation
    estimator = BLECycleHost::CadenceEstimator.new

    estimator.update(packet_with(-6_283, 1_000))

    assert_in_delta 60.0, estimator.cadence_rpm, 0.02
  end

  def test_first_packet_resets_cadence
    estimator = BLECycleHost::CadenceEstimator.new
    estimator.update(packet_with(6_283, 1_000, 1))

    result = estimator.update(
      packet_with(6_283, 1_000, 2, BLECyclePacket::FLAG_FIRST)
    )

    assert_equal false, result
    assert_equal 0.0, estimator.cadence_rpm
  end

  def test_zero_interval_is_rejected
    estimator = BLECycleHost::CadenceEstimator.new

    assert_equal false, estimator.update(packet_with(6_283, 0))
    assert_equal 0.0, estimator.cadence_rpm
  end

  def test_zero_delta_stops_cadence
    estimator = BLECycleHost::CadenceEstimator.new
    estimator.update(packet_with(6_283, 1_000, 1))

    assert_equal true, estimator.update(packet_with(0, 500, 2))
    assert_equal 0.0, estimator.cadence_rpm
  end

  def test_duplicate_packet_does_not_refresh_value
    estimator = BLECycleHost::CadenceEstimator.new
    packet = packet_with(6_283, 1_000, 7)
    estimator.update(packet)

    duplicate = packet_with(3_142, 1_000, 7)
    assert_equal false, estimator.update(duplicate)

    assert_in_delta 60.0, estimator.cadence_rpm, 0.02
    assert_equal 1, estimator.duplicate_count
  end

  private

  def packet_with(delta_angle_mrad, interval_ms, sequence = 1,
                  extra_flags = 0)
    payload = BLECyclePacket.bytes(BLECyclePacket::SIZE)
    BLECyclePacket.encode_into(
      payload,
      BLECyclePacket::FLAG_ANGLE_VALID | extra_flags,
      sequence,
      1_000,
      0,
      delta_angle_mrad,
      interval_ms,
      0
    )
    BLECyclePacket.decode(payload)
  end
end

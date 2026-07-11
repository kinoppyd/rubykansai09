# Usage:
#   ruby -Ilib test/ble_cycle_notification_event_test.rb

require "minitest/autorun"
require "ble_cycle_host/notification_event"

class BLECycleNotificationEventTest < Minitest::Test
  def setup
    @event = BLECycleHost::NotificationEvent.new
  end

  def test_parses_connection_value_handle_and_payload
    packet = notification_packet(0x0040, 8, "cycle")

    assert_equal true, @event.parse(packet)
    assert_equal 0x0040, @event.connection_handle
    assert_equal 8, @event.value_handle
    assert_equal 5, @event.value_length
    assert_equal "cycle", @event.value
  end

  def test_same_value_handle_on_two_connections_remains_distinguishable
    speed = notification_packet(0x0040, 8, "speed")
    cadence = notification_packet(0x0041, 8, "cadence")

    assert_equal true, @event.parse(speed)
    assert_equal 0x0040, @event.connection_handle
    assert_equal 8, @event.value_handle

    assert_equal true, @event.parse(cadence)
    assert_equal 0x0041, @event.connection_handle
    assert_equal 8, @event.value_handle
  end

  def test_different_value_handles_on_one_connection_remain_distinguishable
    assert_equal true, @event.parse(notification_packet(0x0040, 8, "tx"))
    assert_equal 8, @event.value_handle

    assert_equal true, @event.parse(notification_packet(0x0040, 12, "other"))
    assert_equal 12, @event.value_handle
  end

  def test_rejects_wrong_event_type_and_clears_previous_result
    assert_equal true, @event.parse(notification_packet(0x0040, 8, "ok"))

    packet = notification_packet(0x0041, 8, "bad")
    packet.setbyte(0, 0xa6)

    assert_equal false, @event.parse(packet)
    assert_nil @event.connection_handle
    assert_nil @event.value_handle
    assert_nil @event.value
  end

  def test_rejects_truncated_value
    packet = notification_packet(0x0040, 8, "short")
    packet = packet.byteslice(0, packet.bytesize - 1)

    assert_equal false, @event.parse(packet)
  end

  private

  def notification_packet(connection_handle, value_handle, value)
    packet = String.new
    packet << BLECycleHost::NotificationEvent::EVENT_TYPE
    packet << (10 + value.bytesize)
    append_u16(packet, connection_handle)
    append_u16(packet, 0)
    append_u16(packet, 0)
    append_u16(packet, value_handle)
    append_u16(packet, value.bytesize)
    packet << value
    packet
  end

  def append_u16(packet, value)
    packet << (value & 0xff)
    packet << ((value >> 8) & 0xff)
  end
end

require "minitest/autorun"
require "ble_transport/picoruby_peripheral"

class PicoRubyPeripheralTest < Minitest::Test
  def characteristic(uuid)
    BLE::GattDatabase.last.characteristics.find { |c| c[:uuid] == uuid }
  end

  def test_cadence_gatt_uses_native_server_and_excludes_control_point
    feature = BLETransport.u16_le(2)
    runtime = BLETransport::PicoRubyCSCRuntime.new("PicoRuby CSC", feature, 6)

    measurement = characteristic(BLETransport::CSC_MEASUREMENT_UUID)
    assert_equal BLETransport::NOTIFY, measurement[:properties]
    assert_equal BLETransport::DYNAMIC, measurement[:value_properties]
    assert_equal 1, measurement[:descriptors].size
    assert_equal BLETransport::READ | BLETransport::WRITE_WITHOUT_RESPONSE |
                 BLETransport::WRITE | BLETransport::DYNAMIC,
                 measurement[:descriptors][0][0]
    assert_equal BLETransport::READ,
                 characteristic(BLETransport::CSC_FEATURE_UUID)[:properties] & 0xff
    assert_nil characteristic(BLETransport::CSC_CONTROL_POINT_UUID)
    assert_equal [0, 1, 6], runtime.native_init
  end

  def test_gatt_database_contains_mandatory_generic_attribute_service
    BLETransport::PicoRubyCSCRuntime.new("PicoRuby CSC", BLETransport.u16_le(2), 6)

    assert BLE::GattDatabase.last.handle_table.key?(BLETransport::GAP_SERVICE_UUID)
    assert BLE::GattDatabase.last.handle_table.key?(BLETransport::GATT_SERVICE_UUID)
    assert BLE::GattDatabase.last.handle_table.key?(BLETransport::CSC_SERVICE_UUID)
  end

  def test_wheel_gatt_includes_control_point_and_appearance
    feature = BLETransport.u16_le(1)
    runtime = BLETransport::PicoRubyCSCRuntime.new("PicoRuby CSC", feature, 12)

    control = characteristic(BLETransport::CSC_CONTROL_POINT_UUID)
    assert_equal BLETransport::WRITE | BLETransport::INDICATE, control[:properties]
    assert_equal BLETransport::WRITE | BLETransport::DYNAMIC, control[:value_properties]
    assert_equal 1, control[:descriptors].size
    appearance = characteristic(BLETransport::GAP_APPEARANCE_UUID)
    assert_equal [0x82, 0x04], appearance[:value].bytes
    assert_equal [1, 0, 12], runtime.native_init
  end

  def test_advertising_contains_csc_uuid_and_shortens_long_name
    feature = BLETransport.u16_le(2)
    BLETransport::PicoRubyCSCRuntime.new("1234567890123456789", feature, 6)
    fields = BLE::AdvertisingData.last.fields

    assert fields.any? { |f| f[0] == BLETransport::AD_FLAGS }
    assert fields.any? { |f| f[0] == BLETransport::AD_COMPLETE_LIST_16_BIT_SERVICE_UUIDS && f[1].bytes == [0x16, 0x18] }
    name = fields.find { |f| f[0] == BLETransport::AD_SHORTENED_LOCAL_NAME }
    assert_equal 18, name[1].bytesize
    appearance = fields.find { |f| f[0] == BLETransport::AD_APPEARANCE }
    assert_equal [0x83, 0x04], appearance[1].bytes
  end

  def test_native_updates_use_deltas_and_crank_rollover
    runtime = BLETransport::PicoRubyCSCRuntime.new("PicoRuby CSC", BLETransport.u16_le(3), 6)

    runtime.update_measurement(10, 100, 0xffff, 200)
    assert_equal [10, 100, 0xffff, 200], runtime.native_update
    runtime.update_measurement(12, 300, 0, 400)
    assert_equal [2, 300, 1, 400], runtime.native_update
  end

  def test_native_measurement_status_is_exposed_without_allocation
    runtime = BLETransport::PicoRubyCSCRuntime.new("PicoRuby CSC", BLETransport.u16_le(2), 6)

    assert_equal 0, runtime.measurement_status
    runtime.native_measurement_status = 7
    assert_equal 7, runtime.measurement_status
  end

  def test_legacy_payload_parser_does_not_allocate_field_arrays
    runtime = BLETransport::PicoRubyCSCRuntime.new("PicoRuby CSC", BLETransport.u16_le(3), 6)
    payload = "\x03\x03\x00\x00\x00\x00\x04\x07\x00\x00\x06"

    assert_equal true, runtime.notify_measurement(payload)
    assert_equal [3, 1_024, 7, 1_536], runtime.native_update
  end

  def test_le_connection_complete_connects_without_mtu_exchange
    runtime = BLETransport::PicoRubyCSCRuntime.new("PicoRuby CSC", BLETransport.u16_le(2), 6)
    runtime.queue_packet("\x3e\x02\x01\x00")

    runtime.poll_once(100)

    assert_equal true, runtime.connected?
  end

  def test_enhanced_le_connection_complete_versions_connect
    [0x0a, 0x29].each do |subevent|
      runtime = BLETransport::PicoRubyCSCRuntime.new("PicoRuby CSC", BLETransport.u16_le(2), 6)
      runtime.queue_packet("\x3e\x02" + subevent.chr + "\x00")
      runtime.poll_once(100)
      assert_equal true, runtime.connected?
    end
  end

  def test_disconnect_restarts_fast_then_switches_to_slow_advertising
    runtime = BLETransport::PicoRubyCSCRuntime.new("PicoRuby CSC", BLETransport.u16_le(2), 6)
    runtime.queue_packet("\x60\x01\x02")
    runtime.poll_once(100)
    assert_equal [48, 96], runtime.advertisements[-1][1, 2]

    runtime.poll_once(30_099)
    assert_equal 1, runtime.advertisements.size
    runtime.poll_once(30_100)
    assert_equal [1_600, 1_920], runtime.advertisements[-1][1, 2]

    runtime.queue_packet("\x05\x00")
    runtime.poll_once(40_000)
    assert_equal [48, 96], runtime.advertisements[-1][1, 2]
  end

  def test_power_lifecycle_is_idempotent
    runtime = BLETransport::PicoRubyCSCRuntime.new("PicoRuby CSC", BLETransport.u16_le(2), 6)

    assert_equal true, runtime.power_on
    assert_equal false, runtime.power_on
    assert_equal true, runtime.power_off
    assert_equal false, runtime.power_off
    assert_equal [BLE::HCI_POWER_ON, BLE::HCI_POWER_OFF], runtime.power_events
  end
end

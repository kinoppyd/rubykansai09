# Usage:
#   ruby -Ilib test/ble_cycle_multi_uart_central_test.rb

require "minitest/autorun"
require "ble_cycle_host/multi_uart_central"

class BLECycleMultiUARTCentralTest < Minitest::Test
  SPEED_ADDRESS = "88:A2:9E:0B:A7:DE"
  CADENCE_ADDRESS = "88:A2:9E:0B:A8:11"

  class FakeTransport
    attr_reader :event_sink
    attr_reader :listener_calls
    attr_reader :stop_listener_calls
    attr_reader :scan_params
    attr_reader :start_scan_calls
    attr_reader :stop_scan_calls
    attr_reader :gap_connections
    attr_reader :service_discoveries
    attr_reader :characteristic_discoveries
    attr_reader :subscriptions

    def initialize
      @listener_calls = 0
      @stop_listener_calls = 0
      @start_scan_calls = 0
      @stop_scan_calls = 0
      @gap_connections = []
      @service_discoveries = []
      @characteristic_discoveries = []
      @subscriptions = []
    end

    def event_sink=(sink)
      @event_sink = sink
    end

    def debug=(value)
      @debug = value
    end

    def listen_for_all_characteristic_value_updates
      @listener_calls += 1
      0
    end

    def stop_listening_for_all_characteristic_value_updates
      @stop_listener_calls += 1
      0
    end

    def set_scan_params(type, interval, window)
      @scan_params = [type, interval, window]
      0
    end

    def start_scan
      @start_scan_calls += 1
      0
    end

    def stop_scan
      @stop_scan_calls += 1
      0
    end

    def gap_connect(address, address_type)
      @gap_connections << [address, address_type]
      0
    end

    def discover_primary_services(connection_handle)
      @service_discoveries << connection_handle
      0
    end

    def discover_characteristics_for_service(connection_handle, start_handle, end_handle)
      @characteristic_discoveries << [connection_handle, start_handle, end_handle]
      0
    end

    def write_characteristic_descriptor_using_descriptor_handle(connection_handle, descriptor_handle, data)
      @subscriptions << [connection_handle, descriptor_handle, data]
      0
    end

    def start
      yield if block_given?
      0
    end
  end

  def setup
    @transport = FakeTransport.new
    @central = BLECycleHost::MultiUARTCentral.new(
      speed_address: SPEED_ADDRESS,
      cadence_address: CADENCE_ADDRESS,
      transport: @transport
    )
  end

  def test_registers_one_listener_and_starts_one_scan
    assert_same @central, @transport.event_sink
    assert_equal :off, @central.state

    boot
    boot

    assert_equal 1, @transport.listener_calls
    assert_equal [:passive, 0x30, 0x30], @transport.scan_params
    assert_equal 1, @transport.start_scan_calls
    assert_equal :scanning, @central.state
  end

  def test_connects_and_subscribes_two_slots_sequentially
    boot

    connect_and_ready(SPEED_ADDRESS, "PRCycle", 0x0040)

    assert_equal true, @central.speed_ready?
    assert_equal false, @central.cadence_ready?
    assert_equal 1, @central.ready_count
    assert_equal 2, @transport.start_scan_calls

    connect_and_ready(CADENCE_ADDRESS, "PRCad", 0x0041)

    assert_equal true, @central.all_ready?
    assert_equal 2, @central.ready_count
    assert_equal :ready, @central.state
    assert_equal [0x0040, 0x0041], @transport.service_discoveries
    assert_equal [
      [0x0040, 4, 9],
      [0x0041, 4, 9]
    ], @transport.characteristic_discoveries
    assert_equal [
      [0x0040, 9, "\x01\x00"],
      [0x0041, 9, "\x01\x00"]
    ], @transport.subscriptions
  end

  def test_routes_same_tx_handle_by_connection_handle
    boot
    connect_and_ready(SPEED_ADDRESS, "PRCycle", 0x0040)
    connect_and_ready(CADENCE_ADDRESS, "PRCad", 0x0041)
    received = []
    @central.on_packet do |role, packet, reader|
      received << [role, packet.sequence, reader.gap_count]
    end

    @central.handle_event(notification_event(0x0040, 8, cycle_packet(10, 100)))
    @central.handle_event(notification_event(0x0041, 8, cycle_packet(20, 200)))
    @central.handle_event(notification_event(0x0040, 8, cycle_packet(11, 300)))
    @central.handle_event(notification_event(0x0041, 8, cycle_packet(21, 400)))
    @central.handle_event(notification_event(0x0040, 12, cycle_packet(12, 500)))

    assert_equal [
      [:speed, 10, 0],
      [:cadence, 20, 0],
      [:speed, 11, 0],
      [:cadence, 21, 0]
    ], received
    assert_equal 2, @central.speed_slot.notification_count
    assert_equal 2, @central.cadence_slot.notification_count
  end

  def test_disconnect_resets_only_matching_slot_and_rescans
    boot
    connect_and_ready(SPEED_ADDRESS, "PRCycle", 0x0040)
    connect_and_ready(CADENCE_ADDRESS, "PRCad", 0x0041)

    @central.handle_event(disconnection_event(0x0041))

    assert_equal true, @central.speed_ready?
    assert_equal 0x0040, @central.speed_slot.connection_handle
    assert_equal false, @central.cadence_ready?
    assert_equal :missing, @central.slot_state(:cadence)
    assert_equal 1, @central.ready_count
    assert_equal 3, @transport.start_scan_calls
    assert_equal :scanning, @central.state
  end

  def test_address_is_strict_when_configured_and_name_is_fallback_without_address
    boot
    @central.handle_event(advertising_event("88:A2:9E:0B:AF:FF", "PRCycle"))

    assert_equal 0, @transport.gap_connections.length

    transport = FakeTransport.new
    central = BLECycleHost::MultiUARTCentral.new(
      speed_address: SPEED_ADDRESS,
      cadence_address: nil,
      transport: transport
    )
    central.handle_event(btstack_state_event)
    central.handle_event(advertising_event(CADENCE_ADDRESS, "PRCad"))

    assert_equal 1, transport.gap_connections.length
    assert_equal :connecting, central.slot_state(:cadence)
    assert_equal :missing, central.slot_state(:speed)
  end

  def test_cadence_can_connect_before_speed
    boot

    @central.handle_event(advertising_event(CADENCE_ADDRESS, "PRCad"))

    assert_equal :connecting, @central.slot_state(:cadence)
    assert_equal :missing, @central.slot_state(:speed)
    assert_equal CADENCE_ADDRESS, address_string(@transport.gap_connections[0][0])
  end

  def test_fixed_address_does_not_depend_on_advertised_service_uuid
    boot

    @central.handle_event(
      advertising_event(
        SPEED_ADDRESS,
        "unrelated",
        service_uuid: "0000180f-0000-1000-8000-00805f9b34fb"
      )
    )

    assert_equal 1, @transport.gap_connections.length
    assert_equal :connecting, @central.slot_state(:speed)
    assert_equal 1, @central.speed_slot.target_report_count
    assert_equal 0, @central.speed_slot.service_reject_count
  end

  def test_nonconnectable_target_report_is_counted_but_not_connected
    boot

    @central.handle_event(
      advertising_event(SPEED_ADDRESS, "PRCycle", event_type: 0x04)
    )

    assert_equal 0, @transport.gap_connections.length
    assert_equal :missing, @central.slot_state(:speed)
    assert_equal 1, @central.speed_slot.target_report_count
    assert_equal 1, @central.speed_slot.nonconnectable_report_count
  end

  def test_failed_connect_command_resets_pending_slot
    boot
    @central.handle_event(advertising_event(SPEED_ADDRESS, "PRCycle"))

    @central.handle_event(command_status_event(0x0c))

    assert_equal :missing, @central.slot_state(:speed)
    assert_equal :scanning, @central.state
    assert_equal 2, @transport.start_scan_calls
  end

  private

  def boot
    @central.handle_event(btstack_state_event)
  end

  def connect_and_ready(address, name, connection_handle)
    @central.handle_event(advertising_event(address, name))
    @central.handle_event(connection_complete_event(connection_handle))
    @central.handle_event(service_result_event(connection_handle, 4, 9))
    @central.handle_event(query_complete_event(connection_handle))
    @central.handle_event(characteristic_result_event(connection_handle, 6, BLECyclePacket::RX_UUID))
    @central.handle_event(characteristic_result_event(connection_handle, 8, BLECyclePacket::TX_UUID))
    @central.handle_event(query_complete_event(connection_handle))
    @central.handle_event(query_complete_event(connection_handle))
  end

  def btstack_state_event
    [0x60, 1, 2].pack("C*")
  end

  def advertising_event(address, name, event_type: 0x00,
                        service_uuid: BLECyclePacket::SERVICE_UUID)
    data = ad_structure(0x01, "\x06")
    data << ad_structure(0x09, name)
    data << ad_structure(0x07, uuid_le(service_uuid))
    address_bytes = address.split(":").map { |part| part.to_i(16) }.reverse
    params = [0x02, 0x01, event_type, 0x00].pack("C*")
    params << address_bytes.pack("C*")
    params << [data.bytesize].pack("C")
    params << data
    params << [0xc0].pack("C")
    [0x3e, params.bytesize].pack("C*") + params
  end

  def ad_structure(type, value)
    [value.bytesize + 1, type].pack("C*") + value
  end

  def connection_complete_event(connection_handle)
    [0xe7, 4, 0x08, 0x00,
     connection_handle & 0xff, (connection_handle >> 8) & 0xff].pack("C*")
  end

  def command_status_event(status)
    [0x0f, 4, status, 1, 0x0d, 0x20].pack("C*")
  end

  def service_result_event(connection_handle, start_handle, end_handle)
    packet = event_prefix(0xa1, connection_handle)
    append_u16(packet, start_handle)
    append_u16(packet, end_handle)
    packet << uuid_le(BLECyclePacket::SERVICE_UUID)
    set_parameter_length(packet)
  end

  def characteristic_result_event(connection_handle, value_handle, uuid)
    packet = event_prefix(0xa2, connection_handle)
    append_u16(packet, value_handle - 1)
    append_u16(packet, value_handle)
    append_u16(packet, value_handle + 1)
    append_u16(packet, 0)
    packet << uuid_le(uuid)
    set_parameter_length(packet)
  end

  def query_complete_event(connection_handle, status = 0)
    packet = event_prefix(0xa0, connection_handle)
    packet << status
    set_parameter_length(packet)
  end

  def event_prefix(type, connection_handle)
    packet = String.new
    packet << type
    packet << 0
    append_u16(packet, connection_handle)
    append_u16(packet, 0)
    append_u16(packet, 0)
    packet
  end

  def notification_event(connection_handle, value_handle, value)
    packet = event_prefix(0xa7, connection_handle)
    append_u16(packet, value_handle)
    append_u16(packet, value.bytesize)
    packet << value
    set_parameter_length(packet)
  end

  def disconnection_event(connection_handle)
    [0x05, 4, 0,
     connection_handle & 0xff, (connection_handle >> 8) & 0xff,
     0x13].pack("C*")
  end

  def cycle_packet(sequence, delta_angle_mrad)
    payload = BLECyclePacket.bytes(BLECyclePacket::SIZE)
    BLECyclePacket.encode_into(
      payload,
      BLECyclePacket::FLAG_ANGLE_VALID,
      sequence,
      sequence * 500,
      sequence,
      delta_angle_mrad,
      500,
      0
    )
  end

  def set_parameter_length(packet)
    packet.setbyte(1, packet.bytesize - 2)
    packet
  end

  def append_u16(packet, value)
    packet << (value & 0xff)
    packet << ((value >> 8) & 0xff)
  end

  def uuid_le(uuid)
    hex = uuid.delete("-")
    bytes = []
    0.step(hex.length - 2, 2) { |i| bytes << hex[i, 2].to_i(16) }
    bytes.reverse.pack("C*")
  end

  def address_string(address)
    address.bytes.map { |byte| "%02X" % byte }.join(":")
  end
end

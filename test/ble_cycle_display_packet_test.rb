# Usage:
#   ruby -Ilib test/ble_cycle_display_packet_test.rb

require "minitest/autorun"
require "ble_cycle_display_packet"
require "ble_cycle_host/display_output"

module Machine
  def self.delay_ms(_milliseconds)
  end
end

class BLECycleDisplayPacketTest < Minitest::Test
  def test_host_display_status_matches_wire_protocol
    assert_equal BLECycleDisplayPacket::STATUS_BLE_CONNECTED,
                 BLECycleHost::DisplayStatus::BLE_CONNECTED
    assert_equal BLECycleDisplayPacket::STATUS_STALE,
                 BLECycleHost::DisplayStatus::STALE
    assert_equal BLECycleDisplayPacket::STATUS_SEQUENCE_GAP,
                 BLECycleHost::DisplayStatus::SEQUENCE_GAP
    assert_equal BLECycleDisplayPacket::STATUS_SENSOR_ERROR,
                 BLECycleHost::DisplayStatus::SENSOR_ERROR
    assert_equal 16, BLECycleHost::DisplayStatus::SPEED_CONNECTED
    assert_equal 32, BLECycleHost::DisplayStatus::CADENCE_CONNECTED
  end

  def test_encode_and_decode
    payload = BLECycleDisplayPacket.bytes(BLECycleDisplayPacket::SIZE)

    BLECycleDisplayPacket.encode_into(
      payload,
      0x1234,
      3_456,
      BLECycleDisplayPacket::STATUS_BLE_CONNECTED
    )
    packet = BLECycleDisplayPacket.decode(payload)

    assert_equal BLECycleDisplayPacket::VERSION, packet.version
    assert_equal 0x1234, packet.sequence
    assert_equal 3_456, packet.speed_centi_kmh
    assert_equal BLECycleDisplayPacket::STATUS_BLE_CONNECTED, packet.status
  end

  def test_speed_conversion_clamps_to_u16
    assert_equal 0, BLECycleDisplayPacket.speed_to_centi_kmh(-1.0)
    assert_equal 1_234, BLECycleDisplayPacket.speed_to_centi_kmh(12.34)
    assert_equal 0xffff, BLECycleDisplayPacket.speed_to_centi_kmh(700.0)
    assert_in_delta 12.34, BLECycleDisplayPacket.centi_kmh_to_speed(1_234), 0.001
  end

  def test_frame_reader_handles_split_and_joined_frames
    payload1 = BLECycleDisplayPacket.bytes(BLECycleDisplayPacket::SIZE)
    payload2 = BLECycleDisplayPacket.bytes(BLECycleDisplayPacket::SIZE)
    out = BLECycleDisplayPacket::Decoded.new
    reader = BLECycleDisplayPacket::FrameReader.new

    BLECycleDisplayPacket.encode_into(payload1, 1, 100, 0)
    BLECycleDisplayPacket.encode_into(payload2, 2, 200, 0)

    reader.push(payload1.byteslice(0, 2))
    assert_equal false, reader.read(out)

    reader.push(payload1.byteslice(2, 4) + payload2)
    assert_equal true, reader.read(out)
    assert_equal 1, out.sequence
    assert_equal 100, out.speed_centi_kmh

    assert_equal true, reader.read(out)
    assert_equal 2, out.sequence
    assert_equal 200, out.speed_centi_kmh
  end

  def test_frame_reader_drops_until_version
    payload = BLECycleDisplayPacket.bytes(BLECycleDisplayPacket::SIZE)
    out = BLECycleDisplayPacket::Decoded.new
    reader = BLECycleDisplayPacket::FrameReader.new

    BLECycleDisplayPacket.encode_into(payload, 7, 321, 0)
    reader.push("\x00\xff" + payload)

    assert_equal true, reader.read(out)
    assert_equal 2, reader.dropped_bytes
    assert_equal :invalid_version, reader.last_error
    assert_equal 7, out.sequence
  end

  def test_uart_display_output_writes_encoded_frame
    uart = FakeUART.new
    output = BLECycleHost::UARTDisplayOutput.new(uart)

    assert_equal true, output.write(12.34, BLECycleDisplayPacket::STATUS_BLE_CONNECTED)
    packet = BLECycleDisplayPacket.decode(uart.writes[0])

    assert_equal 0, packet.sequence
    assert_equal 1_234, packet.speed_centi_kmh
    assert_equal BLECycleDisplayPacket::STATUS_BLE_CONNECTED, packet.status
    assert_equal 1, output.sequence
  end

  def test_gc9a01_display_output_renders_speed
    meter = FakeMeter.new
    output = BLECycleHost::GC9A01DisplayOutput.new(meter)

    assert_equal [0.0], meter.rendered
    assert_equal true, output.write(23.45, 0)

    assert_equal [0.0, 23.45], meter.rendered
    assert_equal 1, output.sequence
  end

  def test_dual_gc9a01_output_renders_speed_and_cadence
    speed_meter = FakeMeter.new
    cadence_meter = FakeCadenceMeter.new
    output = BLECycleHost::GC9A01DisplayOutput.new(speed_meter, cadence_meter)

    assert_equal [[0.0, 0.0, false, false]], cadence_meter.rendered
    status = BLECycleHost::DisplayStatus::SPEED_CONNECTED
    assert_equal true, output.write(23.45, status, 91.2)

    assert_equal [0.0, 23.45], speed_meter.rendered
    assert_equal [
      [0.0, 0.0, false, false],
      [23.45, 91.2, true, false]
    ], cadence_meter.rendered
    assert_equal 1, output.sequence
  end

  def test_display_startup_sweep_reaches_maximum_and_returns_to_zero
    meter = FakeMeter.new
    output = BLECycleHost::GC9A01DisplayOutput.new(meter)
    frame_count = 0

    result = BLECycleHost::DisplayAnimation.startup_sweep(output, 8, 4) do
      frame_count += 1
    end

    assert_equal true, result
    assert_equal [0.0, 0, 4, 8, 4, 0], meter.rendered
    assert_equal 5, frame_count
    assert_equal 5, output.sequence
  end

  def test_dual_display_startup_sweep_moves_cadence_to_maximum
    speed_meter = FakeMeter.new
    cadence_meter = FakeCadenceMeter.new
    output = BLECycleHost::GC9A01DisplayOutput.new(speed_meter, cadence_meter)

    BLECycleHost::DisplayAnimation.startup_sweep(output, 8, 4, 180)

    assert_equal [
      [0.0, 0.0, false, false],
      [0, 0, false, false],
      [4, 90, false, false],
      [8, 180, false, false],
      [4, 90, false, false],
      [0, 0, false, false]
    ], cadence_meter.rendered
  end

  class FakeUART
    attr_reader :writes

    def initialize
      @writes = []
    end

    def write(payload)
      @writes << payload.dup
      payload.bytesize
    end
  end

  class FakeMeter
    attr_reader :rendered

    def initialize
      @rendered = []
    end

    def render(speed_kmh)
      @rendered << speed_kmh
    end
  end

  class FakeCadenceMeter
    attr_reader :rendered

    def initialize
      @rendered = []
    end

    def render(speed_kmh, cadence_rpm,
               speed_connected = false, cadence_connected = false)
      @rendered << [
        speed_kmh,
        cadence_rpm,
        speed_connected,
        cadence_connected
      ]
    end
  end
end

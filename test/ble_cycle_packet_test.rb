# Usage:
#   ruby -Ilib test/ble_cycle_packet_test.rb

require "minitest/autorun"
require "ble_cycle_packet"

class BLECyclePacketTest < Minitest::Test
  def test_encode_byte_layout
    payload = BLECyclePacket.bytes(BLECyclePacket::SIZE)
    BLECyclePacket.encode_into(
      payload,
      BLECyclePacket::FLAG_ANGLE_VALID | BLECyclePacket::FLAG_ROTATION_CHANGED,
      0x1234,
      0x89abcdef,
      42,
      -3142,
      500,
      0x55aa
    )

    assert_equal [
      1, 6, 0x34, 0x12,
      0xef, 0xcd, 0xab, 0x89,
      42, 0, 0, 0,
      0xba, 0xf3, 0xff, 0xff,
      0xf4, 0x01,
      0xaa, 0x55
    ], payload.bytes
  end

  def test_decode_signed_fields
    payload = BLECyclePacket.bytes(BLECyclePacket::SIZE)
    BLECyclePacket.encode_into(payload, 1, 7, 1_000, -2, -1, 250, 3)

    out = BLECyclePacket.decode(payload)

    assert_equal 1, out.version
    assert_equal 1, out.flags
    assert_equal 7, out.sequence
    assert_equal 1_000, out.sensor_time_ms
    assert_equal(-2, out.total_revolutions)
    assert_equal(-1, out.delta_angle_mrad)
    assert_equal 250, out.interval_ms
    assert_equal 3, out.status
  end

  def test_decode_rejects_short_payload
    assert_raises(ArgumentError) do
      BLECyclePacket.decode("\x01\x02")
    end
  end

  def test_decode_into_returns_false_for_wrong_version
    payload = BLECyclePacket.bytes(BLECyclePacket::SIZE)
    out = BLECyclePacket::Decoded.new

    assert_equal false, BLECyclePacket.decode_into(payload, out)
  end

  def test_frame_reader_reads_split_frame
    frame = encoded_frame(1, 123)
    reader = BLECyclePacket::FrameReader.new
    out = BLECyclePacket::Decoded.new

    assert_equal 7, reader.push(frame.byteslice(0, 7))
    assert_equal false, reader.read(out)
    assert_equal 13, reader.push(frame.byteslice(7, 13))
    assert_equal true, reader.read(out)
    assert_equal 1, out.sequence
    assert_equal 123, out.delta_angle_mrad
    assert_equal 0, reader.pending_bytes
  end

  def test_frame_reader_reads_concatenated_frames
    frame1 = encoded_frame(0xffff, 1)
    frame2 = encoded_frame(0, 2)
    reader = BLECyclePacket::FrameReader.new
    out = BLECyclePacket::Decoded.new

    reader.push(frame1 + frame2)

    assert_equal true, reader.read(out)
    assert_equal 0xffff, out.sequence
    assert_equal 0, reader.last_gap
    assert_equal true, reader.read(out)
    assert_equal 0, out.sequence
    assert_equal 0, reader.last_gap
    assert_equal 0, reader.gap_count
  end

  def test_frame_reader_reports_sequence_gap
    reader = BLECyclePacket::FrameReader.new
    out = BLECyclePacket::Decoded.new
    reader.push(encoded_frame(10, 1) + encoded_frame(12, 2))

    assert_equal true, reader.read(out)
    assert_equal true, reader.read(out)
    assert_equal 1, reader.last_gap
    assert_equal 1, reader.gap_count
  end

  def test_frame_reader_drops_invalid_leading_byte
    reader = BLECyclePacket::FrameReader.new
    out = BLECyclePacket::Decoded.new
    reader.push("x" + encoded_frame(3, 4))

    assert_equal true, reader.read(out)
    assert_equal 3, out.sequence
    assert_equal 1, reader.dropped_bytes
    assert_equal :invalid_version, reader.last_error
  end

  private

  def encoded_frame(sequence, delta_angle_mrad)
    payload = BLECyclePacket.bytes(BLECyclePacket::SIZE)
    BLECyclePacket.encode_into(
      payload,
      BLECyclePacket::FLAG_ANGLE_VALID,
      sequence,
      sequence * 100,
      sequence,
      delta_angle_mrad,
      500,
      0
    )
  end
end

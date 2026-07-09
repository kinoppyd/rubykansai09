# Fixed-size binary packet helpers for the custom BLE cycle computer demo.
# The packet is intentionally 20 bytes so it fits in the default BLE ATT MTU.

module BLECyclePacket
  VERSION = 1
  SIZE = 20

  SERVICE_UUID = "6b3f0001-7a2d-4f6b-9af0-5c1a85f3d701"
  RX_UUID = "6b3f0002-7a2d-4f6b-9af0-5c1a85f3d701"
  TX_UUID = "6b3f0003-7a2d-4f6b-9af0-5c1a85f3d701"

  FLAG_FIRST = 1
  FLAG_ANGLE_VALID = 2
  FLAG_ROTATION_CHANGED = 4
  FLAG_SATURATED = 8
  FLAG_DT_SKIPPED = 16
  FLAG_I2C_ERROR = 32
  FLAG_SIGNED_SPEED = 64

  class Decoded
    attr_accessor :version
    attr_accessor :flags
    attr_accessor :sequence
    attr_accessor :sensor_time_ms
    attr_accessor :total_revolutions
    attr_accessor :delta_angle_mrad
    attr_accessor :interval_ms
    attr_accessor :status
  end

  class FrameReader
    attr_reader :dropped_bytes
    attr_reader :last_error
    attr_reader :last_sequence
    attr_reader :last_gap
    attr_reader :gap_count

    def initialize
      @buffer = String.new
      @dropped_bytes = 0
      @last_error = nil
      @last_sequence = nil
      @last_gap = 0
      @gap_count = 0
    end

    def push(bytes)
      return 0 if bytes.nil?
      return 0 if bytes.bytesize == 0
      @buffer << bytes
      bytes.bytesize
    end

    def pending_bytes
      @buffer.bytesize
    end

    def read(out)
      loop do
        return false if @buffer.bytesize < SIZE
        if @buffer.getbyte(0) != VERSION
          drop(1)
          @last_error = :invalid_version
          next
        end
        return false unless BLECyclePacket.decode_into(@buffer, out)
        consume(SIZE)
        check_sequence(out.sequence)
        return true
      end
    end

    def clear
      @buffer = String.new
      @last_error = nil
      @last_sequence = nil
      @last_gap = 0
      @gap_count = 0
      self
    end

    private

    def consume(n)
      @buffer = @buffer.byteslice(n, @buffer.bytesize - n) || String.new
    end

    def drop(n)
      @dropped_bytes += n
      consume(n)
    end

    def check_sequence(seq)
      if @last_sequence
        expected = (@last_sequence + 1) & 0xffff
        @last_gap = (seq - expected) & 0xffff
        @gap_count += 1 if @last_gap != 0
      else
        @last_gap = 0
      end
      @last_sequence = seq
    end
  end

  def self.bytes(n)
    s = String.new
    i = 0
    while i < n
      s << 0
      i += 1
    end
    s
  end

  def self.encode_into(payload, flags, sequence, sensor_time_ms,
                       total_revolutions, delta_angle_mrad, interval_ms,
                       status)
    check_size(payload)
    put_u8(payload, 0, VERSION)
    put_u8(payload, 1, flags)
    put_u16(payload, 2, sequence)
    put_u32(payload, 4, sensor_time_ms)
    put_s32(payload, 8, total_revolutions)
    put_s32(payload, 12, delta_angle_mrad)
    put_u16(payload, 16, interval_ms)
    put_u16(payload, 18, status)
    payload
  end

  def self.decode(payload)
    out = Decoded.new
    decode_into(payload, out)
    out
  end

  def self.decode_into(payload, out)
    check_size(payload)
    return false unless payload.getbyte(0) == VERSION
    out.version = payload.getbyte(0)
    out.flags = payload.getbyte(1)
    out.sequence = get_u16(payload, 2)
    out.sensor_time_ms = get_u32(payload, 4)
    out.total_revolutions = get_s32(payload, 8)
    out.delta_angle_mrad = get_s32(payload, 12)
    out.interval_ms = get_u16(payload, 16)
    out.status = get_u16(payload, 18)
    true
  end

  def self.put_u8(s, i, v)
    s.setbyte(i, v & 255)
  end

  def self.put_u16(s, i, v)
    v &= 0xffff
    s.setbyte(i, v & 255)
    s.setbyte(i + 1, (v >> 8) & 255)
  end

  def self.put_u32(s, i, v)
    v &= 0xffffffff
    s.setbyte(i, v & 255)
    s.setbyte(i + 1, (v >> 8) & 255)
    s.setbyte(i + 2, (v >> 16) & 255)
    s.setbyte(i + 3, (v >> 24) & 255)
  end

  def self.put_s32(s, i, v)
    put_u32(s, i, v)
  end

  def self.get_u16(s, i)
    (s.getbyte(i) || 0) | ((s.getbyte(i + 1) || 0) << 8)
  end

  def self.get_u32(s, i)
    (s.getbyte(i) || 0) |
      ((s.getbyte(i + 1) || 0) << 8) |
      ((s.getbyte(i + 2) || 0) << 16) |
      ((s.getbyte(i + 3) || 0) << 24)
  end

  def self.get_s32(s, i)
    v = get_u32(s, i)
    v >= 0x80000000 ? v - 0x100000000 : v
  end

  def self.check_size(payload)
    if payload.nil? || payload.bytesize < SIZE
      raise ArgumentError, "payload must be at least 20 bytes"
    end
  end
end

# Fixed-size host-to-display packet for the custom BLE cycle computer demo.

module BLECycleDisplayPacket
  VERSION = 1
  SIZE = 6

  STATUS_BLE_CONNECTED = 1
  STATUS_STALE = 2
  STATUS_SEQUENCE_GAP = 4
  STATUS_SENSOR_ERROR = 8

  class Decoded
    attr_accessor :version
    attr_accessor :sequence
    attr_accessor :speed_centi_kmh
    attr_accessor :status
  end

  class FrameReader
    attr_reader :dropped_bytes
    attr_reader :last_error

    def initialize
      @buffer = String.new
      @dropped_bytes = 0
      @last_error = nil
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
        return false unless BLECycleDisplayPacket.decode_into(@buffer, out)
        consume(SIZE)
        return true
      end
    end

    private

    def consume(n)
      @buffer = @buffer.byteslice(n, @buffer.bytesize - n) || String.new
    end

    def drop(n)
      @dropped_bytes += n
      consume(n)
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

  def self.encode_into(payload, sequence, speed_centi_kmh, status)
    check_size(payload)
    put_u8(payload, 0, VERSION)
    put_u16(payload, 1, sequence)
    put_u16(payload, 3, speed_centi_kmh)
    put_u8(payload, 5, status)
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
    out.sequence = get_u16(payload, 1)
    out.speed_centi_kmh = get_u16(payload, 3)
    out.status = payload.getbyte(5)
    true
  end

  def self.speed_to_centi_kmh(speed_kmh)
    value = (speed_kmh * 100.0).to_i
    return 0 if value < 0
    return 0xffff if value > 0xffff
    value
  end

  def self.centi_kmh_to_speed(speed_centi_kmh)
    speed_centi_kmh / 100.0
  end

  def self.put_u8(s, i, v)
    s.setbyte(i, v & 255)
  end

  def self.put_u16(s, i, v)
    v &= 0xffff
    s.setbyte(i, v & 255)
    s.setbyte(i + 1, (v >> 8) & 255)
  end

  def self.get_u16(s, i)
    (s.getbyte(i) || 0) | ((s.getbyte(i + 1) || 0) << 8)
  end

  def self.check_size(payload)
    if payload.nil? || payload.bytesize < SIZE
      raise ArgumentError, "payload must be at least 6 bytes"
    end
  end
end

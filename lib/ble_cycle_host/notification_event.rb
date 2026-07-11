# Parser for BTstack GATT_EVENT_NOTIFICATION packets.

module BLECycleHost
  class NotificationEvent
    EVENT_TYPE = 0xa7
    HEADER_SIZE = 12

    attr_reader :connection_handle
    attr_reader :value_handle
    attr_reader :value_length

    def initialize
      reset
    end

    def parse(packet)
      reset
      return false if packet.nil? || packet.bytesize < HEADER_SIZE
      return false unless packet.getbyte(0) == EVENT_TYPE

      length = get_u16(packet, 10)
      return false if packet.bytesize < HEADER_SIZE + length

      @packet = packet
      @connection_handle = get_u16(packet, 2)
      @value_handle = get_u16(packet, 8)
      @value_length = length
      true
    end

    def value
      return nil unless @packet
      @packet.byteslice(HEADER_SIZE, @value_length)
    end

    private

    def reset
      @packet = nil
      @connection_handle = nil
      @value_handle = nil
      @value_length = 0
    end

    def get_u16(packet, offset)
      packet.getbyte(offset) | (packet.getbyte(offset + 1) << 8)
    end
  end
end

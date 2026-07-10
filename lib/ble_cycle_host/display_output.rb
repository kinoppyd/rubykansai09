# Host-side display outputs for 2-board and 3-board cycle computer layouts.

module BLECycleHost
  module DisplayStatus
    BLE_CONNECTED = 1
    STALE = 2
    SEQUENCE_GAP = 4
    SENSOR_ERROR = 8
  end

  class NullDisplayOutput
    def active?
      false
    end

    def sequence
      0
    end

    def last_sequence
      0
    end

    def write(_speed_kmh, _status)
      false
    end
  end

  class UARTDisplayOutput
    attr_reader :sequence
    attr_reader :last_sequence

    def initialize(uart)
      require "ble_cycle_display_packet"
      @uart = uart
      @payload = BLECycleDisplayPacket.bytes(BLECycleDisplayPacket::SIZE)
      @sequence = 0
      @last_sequence = 0
    end

    def active?
      true
    end

    def write(speed_kmh, status)
      seq = @sequence
      BLECycleDisplayPacket.encode_into(
        @payload,
        seq,
        BLECycleDisplayPacket.speed_to_centi_kmh(speed_kmh),
        status
      )
      @uart.write(@payload)
      @last_sequence = seq
      @sequence = (@sequence + 1) & 0xffff
      true
    end
  end

  class GC9A01DisplayOutput
    attr_reader :sequence
    attr_reader :last_sequence

    def initialize(meter)
      @meter = meter
      @sequence = 0
      @last_sequence = 0
      @meter.render(0.0)
    end

    def active?
      true
    end

    def write(speed_kmh, _status)
      @meter.render(speed_kmh)
      @last_sequence = @sequence
      @sequence = (@sequence + 1) & 0xffff
      true
    end
  end
end

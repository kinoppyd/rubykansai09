# Host-side display outputs for 2-board and 3-board cycle computer layouts.

module BLECycleHost
  module DisplayStatus
    BLE_CONNECTED = 1
    STALE = 2
    SEQUENCE_GAP = 4
    SENSOR_ERROR = 8
    SPEED_CONNECTED = 16
    CADENCE_CONNECTED = 32
  end

  module DisplayAnimation
    def self.startup_sweep(output, max_speed_kmh, step_kmh,
                           max_cadence_rpm = 0)
      return false unless output.active?
      return false if max_speed_kmh <= 0 || step_kmh <= 0

      output.write(0, 0, 0)
      yield if block_given?

      speed = step_kmh
      while speed < max_speed_kmh
        cadence = speed * max_cadence_rpm / max_speed_kmh
        output.write(speed, 0, cadence)
        yield if block_given?
        speed += step_kmh
      end

      output.write(max_speed_kmh, 0, max_cadence_rpm)
      Machine.delay_ms(40)
      yield if block_given?

      speed = max_speed_kmh - step_kmh
      while speed > 0
        cadence = speed * max_cadence_rpm / max_speed_kmh
        output.write(speed, 0, cadence)
        yield if block_given?
        speed -= step_kmh
      end

      output.write(0, 0, 0)
      yield if block_given?
      true
    end
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

    def write(_speed_kmh, _status, _cadence_rpm = 0.0)
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

    def write(speed_kmh, status, _cadence_rpm = 0.0)
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

    def initialize(meter, cadence_meter = nil)
      @meter = meter
      @cadence_meter = cadence_meter
      @sequence = 0
      @last_sequence = 0
      @meter.render(0.0)
      @cadence_meter.render(0.0, 0.0) if @cadence_meter
    end

    def active?
      true
    end

    def write(speed_kmh, status, cadence_rpm = 0.0)
      @meter.render(speed_kmh)
      if @cadence_meter
        speed_connected = (status & DisplayStatus::SPEED_CONNECTED) != 0
        cadence_connected = (status & DisplayStatus::CADENCE_CONNECTED) != 0
        @cadence_meter.render(
          speed_kmh,
          cadence_rpm,
          speed_connected,
          cadence_connected
        )
      end
      @last_sequence = @sequence
      @sequence = (@sequence + 1) & 0xffff
      true
    end
  end
end

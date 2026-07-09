# BLE::UART central wrapper for the custom cycle host demo.

require "ble"
require "ble_cycle_packet"

module BLECycleHost
  class UARTCentral
    attr_reader :reader
    attr_reader :packet

    def initialize
      @uart = BLE::UART.new(
        role: :central,
        service_uuid: BLECyclePacket::SERVICE_UUID,
        rx_uuid: BLECyclePacket::RX_UUID,
        tx_uuid: BLECyclePacket::TX_UUID
      )
      @reader = BLECyclePacket::FrameReader.new
      @packet = BLECyclePacket::Decoded.new
    end

    def debug=(value)
      @uart.debug = value
    end

    def connected?
      @uart.connected?
    end

    def write(payload)
      @uart.write(payload)
    end

    def start
      @uart.start do
        drain_uart
        while @reader.read(@packet)
          yield @packet, @reader if block_given?
        end
      end
    end

    def drain_uart
      while @uart.available?
        data = @uart.read_nonblock(64)
        @reader.push(data) if data
      end
    end
  end
end

# BLE::UART central wrapper for the custom cycle host demo.

require "ble"
require "ble_cycle_packet"
require "ble_cycle_host/uart_central_patch"

module BLECycleHost
  class UARTCentral
    attr_reader :reader
    attr_reader :packet

    def initialize(target_name = "PRCycle", target_address = nil)
      @uart = BLE::UART.new(
        role: :central,
        service_uuid: BLECyclePacket::SERVICE_UUID,
        rx_uuid: BLECyclePacket::RX_UUID,
        tx_uuid: BLECyclePacket::TX_UUID
      )
      @uart.cycle_target_name = target_name
      @uart.cycle_target_address = target_address
      @reader = BLECyclePacket::FrameReader.new
      @packet = BLECyclePacket::Decoded.new
    end

    def debug=(value)
      @uart.debug = value
    end

    def scan_debug=(value)
      @uart.cycle_scan_debug = value
    end

    def connected?
      @uart.connected?
    end

    def state
      @uart.cycle_central_state
    end

    def scan_reports
      @uart.cycle_scan_report_count
    end

    def write(payload)
      @uart.write(payload)
    end

    def start
      @uart.start do
        drain_uart
        delivered = false
        while @reader.read(@packet)
          delivered = true
          yield @packet, @reader if block_given?
        end
        yield nil, @reader if block_given? && !delivered
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

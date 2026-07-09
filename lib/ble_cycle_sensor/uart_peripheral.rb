# BLE::UART peripheral wrapper for the custom cycle sensor demo.

require "ble"
require "ble_cycle_packet"

class BLE
  class UART < BLE
    private

    def _check_cccd
      while (data = pop_write_value(@cccd_handle))
        @notification_enabled = (data == "\x01\x00")
        @connected = @notification_enabled
        debug_puts "Notifications #{@notification_enabled ? 'enabled' : 'disabled'}"
      end
    end
  end
end

module BLECycleSensor
  class UARTPeripheral
    def initialize(name = "PRCycle")
      @uart = BLE::UART.new(
        role: :peripheral,
        name: name,
        service_uuid: BLECyclePacket::SERVICE_UUID,
        rx_uuid: BLECyclePacket::RX_UUID,
        tx_uuid: BLECyclePacket::TX_UUID
      )
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

    def available?
      @uart.available?
    end

    def read_nonblock(nbytes = 64)
      @uart.read_nonblock(nbytes)
    end

    def start(&block)
      @uart.start(&block)
    end
  end
end

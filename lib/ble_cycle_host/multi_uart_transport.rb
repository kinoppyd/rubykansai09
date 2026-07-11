# BLE::UART transport that delegates central events to MultiUARTCentral.

require "ble"

module BLECycleHost
  class MultiUARTTransport < ::BLE::UART
    attr_writer :event_sink

    private

    def _central_packet_callback(event_packet)
      @event_sink.handle_event(event_packet) if @event_sink
    end
  end
end

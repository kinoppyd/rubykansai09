# BLE::UART transport that delegates central events to MultiUARTCentral.

require "ble"

module BLECycleHost
  class MultiUARTTransport < ::BLE::UART
    MAX_EVENT_PACKETS_PER_TICK = 8

    attr_writer :event_sink

    # BLE::UART drains the event queue completely before calling the user
    # block. A busy scan can keep that queue non-empty indefinitely, so bound
    # the work per tick while preserving the UART polling cadence.
    def start(timeout_ms = nil, &block)
      @user_block = block
      total_timeout_ms = 0
      tick_ms = POLLING_UNIT_MS / USER_BLOCK_CALL_COUNT_PER_POLL
      hci_power_control(HCI_POWER_ON)

      while true
        break if timeout_ms && timeout_ms <= total_timeout_ms

        packet_count = 0
        while packet_count < MAX_EVENT_PACKETS_PER_TICK
          packet = pop_packet
          break unless packet
          packet_callback(packet)
          packet_count += 1
        end
        while pop_heartbeat
          heartbeat_callback
        end
        _flush_tx_central if @connected
        @user_block&.call
        sleep_ms tick_ms
        total_timeout_ms += tick_ms
      end

      total_timeout_ms
    ensure
      hci_power_control(HCI_POWER_OFF)
      @ensure_proc&.call
    end

    private

    def _central_packet_callback(event_packet)
      @event_sink.handle_event(event_packet) if @event_sink
    end
  end
end

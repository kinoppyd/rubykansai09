# Usage:
#   ruby -Ilib test/ble_cycle_multi_uart_transport_test.rb

require "minitest/autorun"

class BLE
  HCI_POWER_OFF = 0
  HCI_POWER_ON = 1
  POLLING_UNIT_MS = 100

  class UART < BLE
    USER_BLOCK_CALL_COUNT_PER_POLL = 5

    def packet_callback(packet)
      _central_packet_callback(packet)
    end
  end
end

$LOADED_FEATURES << "ble.rb" unless $LOADED_FEATURES.include?("ble.rb")
require "ble_cycle_host/multi_uart_transport"

class BLECycleMultiUARTTransportTest < Minitest::Test
  class StopLoop < StandardError
  end

  class EventSink
    attr_reader :count

    def initialize
      @count = 0
    end

    def handle_event(_packet)
      @count += 1
    end
  end

  def test_calls_user_block_even_when_event_source_never_becomes_empty
    transport = BLECycleHost::MultiUARTTransport.allocate
    sink = EventSink.new
    power_states = []
    sleeps = []
    callbacks = 0

    transport.event_sink = sink
    transport.define_singleton_method(:hci_power_control) { |state| power_states << state }
    transport.define_singleton_method(:pop_packet) { "event" }
    transport.define_singleton_method(:pop_heartbeat) { false }
    transport.define_singleton_method(:sleep_ms) { |milliseconds| sleeps << milliseconds }

    assert_raises(StopLoop) do
      transport.start do
        callbacks += 1
        raise StopLoop if callbacks == 2
      end
    end

    assert_equal 2, callbacks
    assert_equal 16, sink.count
    assert_equal [20], sleeps
    assert_equal [BLE::HCI_POWER_ON, BLE::HCI_POWER_OFF], power_states
  end
end

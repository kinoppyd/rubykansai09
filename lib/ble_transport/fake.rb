# Usage:
#   require "ble_transport/fake"
#   require "ble_csc_service"
#   transport = BLETransport::Fake.new
#   service = BLECSCService.new(transport)
#   service.start
#   service.update_wheel(1, 1000)
#   service.notify(1000)
#   bytes = transport.notifications[0][:bytes]
#
# Test transport for BLECSCService. It records setup values and notification
# payloads without requiring BLE hardware or the PicoRuby BLE runtime.

require "ble_transport"

module BLETransport
  class Fake
    attr_reader :name, :feature_payload, :sensor_location, :notifications

    def initialize
      @connected = true
      @notifications = []
      @next_handle = 1
    end

    def setup_csc(name, feature_payload, sensor_location)
      @name = name
      @feature_payload = feature_payload
      @sensor_location = sensor_location
      h = @next_handle
      @next_handle += 1
      h
    end

    def notify(characteristic, bytes)
      @notifications << {
        :handle => characteristic,
        :bytes => bytes.dup
      }
      true
    end

    def connected?
      @connected
    end

    def connected=(v)
      @connected = !!v
    end

    def poll
      true
    end
  end
end

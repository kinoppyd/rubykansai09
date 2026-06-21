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

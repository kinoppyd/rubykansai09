require "ble"
require "ble_transport"

module BLETransport
  class PicoRubyPeripheral
    def initialize
      @runtime = nil
    end

    def setup_csc(name, feature_payload, sensor_location)
      @runtime = PicoRubyCSCRuntime.new(name, feature_payload, sensor_location)
      @runtime.measurement_handle
    end

    def notify(_characteristic, bytes)
      @runtime.notify_measurement(bytes)
    end

    def connected?
      @runtime && @runtime.connected?
    end

    def start(timeout_ms = nil)
      @runtime.start(timeout_ms)
    end

    def poll
      @runtime.poll_once
    end
  end

  class PicoRubyCSCRuntime < ::BLE
    BTSTACK_EVENT_STATE = 0x60
    HCI_EVENT_DISCONNECTION_COMPLETE = 0x05
    ATT_EVENT_MTU_EXCHANGE_COMPLETE = 0xB5

    def initialize(name, feature_payload, sensor_location)
      @notify_enabled = false
      @advertising_started = false
      @connected = false
      @adv_data = nil
      @measurement_handle = nil
      @cccd_handle = nil

      db = ::BLE::GattDatabase.new do |g|
        g.add_service(GATT_PRIMARY_SERVICE_UUID, GAP_SERVICE_UUID) do |s|
          s.add_characteristic(READ, GAP_DEVICE_NAME_UUID, READ, name)
        end

        g.add_service(GATT_PRIMARY_SERVICE_UUID, CSC_SERVICE_UUID) do |s|
          s.add_characteristic(NOTIFY | DYNAMIC, CSC_MEASUREMENT_UUID, NOTIFY | DYNAMIC, "") do |c|
            c.add_descriptor(READ | WRITE | DYNAMIC, CLIENT_CHARACTERISTIC_CONFIGURATION, "\x00\x00")
          end
          s.add_characteristic(READ | DYNAMIC, CSC_FEATURE_UUID, READ | DYNAMIC, feature_payload)
          if sensor_location
            s.add_characteristic(READ | DYNAMIC, CSC_SENSOR_LOCATION_UUID, READ | DYNAMIC, BLETransport.u8(sensor_location))
          end
        end
      end

      table = db.handle_table[CSC_SERVICE_UUID][CSC_MEASUREMENT_UUID]
      @measurement_handle = table[:value_handle]
      @cccd_handle = table[CLIENT_CHARACTERISTIC_CONFIGURATION]
      @adv_data = advertising_data(name)
      super(:peripheral, db.profile_data)
    end

    def measurement_handle
      @measurement_handle
    end

    def connected?
      @connected
    end

    def start_advertising
      return true if @advertising_started
      advertise(@adv_data)
      @advertising_started = true
      true
    end

    def notify_measurement(bytes)
      return false unless @notify_enabled
      push_read_value(@measurement_handle, bytes)
      notify(@measurement_handle)
      true
    end

    def start(timeout_ms = nil)
      t = 0
      hci_power_control(HCI_POWER_ON)
      loop do
        break if timeout_ms && timeout_ms <= t
        poll_once
        sleep_ms POLLING_UNIT_MS
        t += POLLING_UNIT_MS
      end
      t
    end

    def poll_once
      while (p = pop_packet)
        packet_callback(p)
      end
      while pop_heartbeat
        check_cccd
      end
    end

    def packet_callback(p)
      e = p.getbyte(0)
      if e == BTSTACK_EVENT_STATE
        start_advertising if p.getbyte(2) == HCI_STATE_WORKING
      elsif e == HCI_EVENT_DISCONNECTION_COMPLETE
        @connected = false
        @advertising_started = false
        @notify_enabled = false
        start_advertising
      elsif e == ATT_EVENT_MTU_EXCHANGE_COMPLETE
        @connected = true
      end
    end

    def check_cccd
      while (d = pop_write_value(@cccd_handle))
        @notify_enabled = d == "\x01\x00"
      end
    end

    def advertising_data(name)
      ::BLE::AdvertisingData.build do |a|
        a.add(AD_FLAGS, APP_AD_FLAGS)
        a.add(AD_COMPLETE_LOCAL_NAME, name)
        a.add(AD_COMPLETE_LIST_16_BIT_SERVICE_UUIDS, BLETransport.u16_le(CSC_SERVICE_UUID))
      end
    end
  end
end

# Usage:
#   require "ble_transport/picoruby_peripheral"
#   require "mpu_6050_ble_csc"
#   ble = BLETransport::PicoRubyPeripheral.new
#   sensor = MPU6050BLECSC.new(mpu, ble, "PicoRuby CSC", nil, :x)
#   sensor.start
#   ble.start(1000)
#   loop do
#     sensor.tick
#     ble.poll
#   end
#
# PicoRuby BLE peripheral transport for the Cycling Speed and Cadence
# service. Use this only on a PicoRuby/R2P2 build that includes the "ble"
# gem and a supported BLE board such as Pico W or Pico 2 W.

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

    def notify_csc(wheel_revolutions, wheel_time, crank_revolutions, crank_time)
      @runtime.update_measurement(wheel_revolutions, wheel_time, crank_revolutions, crank_time)
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
    MAX_ATT_DB_SIZE = 512
    MAX_AD_NAME_BYTES = 18

    def initialize(name, feature_payload, sensor_location)
      @advertising_started = false
      @connected = false
      @adv_data = nil
      @measurement_handle = nil
      @last_wheel_revolutions = 0
      @last_crank_revolutions = 0

      feature = BLETransport.get_u16(feature_payload, 0)
      @wheel_supported = (feature & 1) != 0
      @crank_supported = (feature & 2) != 0
      appearance = if @wheel_supported && @crank_supported
        APPEARANCE_SPEED_AND_CADENCE
      elsif @wheel_supported
        APPEARANCE_SPEED
      else
        APPEARANCE_CADENCE
      end
      appearance_payload = BLETransport.u16_le(appearance)

      db = ::BLE::GattDatabase.new do |g|
        g.add_service(GATT_PRIMARY_SERVICE_UUID, GAP_SERVICE_UUID) do |s|
          s.add_characteristic(READ, GAP_DEVICE_NAME_UUID, READ, name)
          s.add_characteristic(READ, GAP_APPEARANCE_UUID, READ, appearance_payload)
        end

        g.add_service(GATT_PRIMARY_SERVICE_UUID, CSC_SERVICE_UUID) do |s|
          s.add_characteristic(NOTIFY, CSC_MEASUREMENT_UUID, DYNAMIC, "") do |c|
            c.add_descriptor(READ | WRITE | DYNAMIC, CLIENT_CHARACTERISTIC_CONFIGURATION, "\x00\x00")
          end
          s.add_characteristic(READ | DYNAMIC, CSC_FEATURE_UUID, READ | DYNAMIC, feature_payload)
          if sensor_location
            s.add_characteristic(READ | DYNAMIC, CSC_SENSOR_LOCATION_UUID, READ | DYNAMIC, BLETransport.u8(sensor_location))
          end
          if @wheel_supported
            s.add_characteristic(WRITE | INDICATE, CSC_CONTROL_POINT_UUID, WRITE | DYNAMIC, "") do |c|
              c.add_descriptor(READ | WRITE | DYNAMIC, CLIENT_CHARACTERISTIC_CONFIGURATION, "\x00\x00")
            end
          end
        end
      end

      table = db.handle_table[CSC_SERVICE_UUID][CSC_MEASUREMENT_UUID]
      @measurement_handle = table[:value_handle]
      raise "CSCS ATT database exceeds 512 bytes" if MAX_ATT_DB_SIZE < db.profile_data.bytesize
      @adv_data = advertising_data(name, appearance_payload)
      super(:peripheral, db.profile_data)
      csc_server_init(@wheel_supported ? 1 : 0, @crank_supported ? 1 : 0)
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
      i = 1
      wheel_revolutions = 0
      wheel_time = 0
      crank_revolutions = 0
      crank_time = 0
      if (bytes.getbyte(0) & 1) != 0
        wheel_revolutions = BLETransport.get_u32(bytes, i)
        wheel_time = BLETransport.get_u16(bytes, i + 4)
        i += 6
      end
      if (bytes.getbyte(0) & 2) != 0
        crank_revolutions = BLETransport.get_u16(bytes, i)
        crank_time = BLETransport.get_u16(bytes, i + 2)
      end
      update_measurement(wheel_revolutions, wheel_time, crank_revolutions, crank_time)
    end

    def update_measurement(wheel_revolutions, wheel_time, crank_revolutions, crank_time)
      wheel_delta = wheel_revolutions - @last_wheel_revolutions
      crank_delta = (crank_revolutions - @last_crank_revolutions) & 0xffff
      @last_wheel_revolutions = wheel_revolutions
      @last_crank_revolutions = crank_revolutions
      csc_server_update(wheel_delta, wheel_time, crank_delta, crank_time)
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
        # Native CSC server owns CCCD state; only drain the periodic flag.
      end
    end

    def packet_callback(p)
      e = p.getbyte(0)
      if e == BTSTACK_EVENT_STATE
        start_advertising if p.getbyte(2) == HCI_STATE_WORKING
      elsif e == HCI_EVENT_DISCONNECTION_COMPLETE
        @connected = false
        @advertising_started = false
        start_advertising
      elsif e == ATT_EVENT_MTU_EXCHANGE_COMPLETE
        @connected = true
      end
    end

    def advertising_data(name, appearance_payload)
      ad_name = name
      name_type = AD_COMPLETE_LOCAL_NAME
      if MAX_AD_NAME_BYTES < name.bytesize
        ad_name = name.byteslice(0, MAX_AD_NAME_BYTES)
        name_type = AD_SHORTENED_LOCAL_NAME
      end
      ::BLE::AdvertisingData.build do |a|
        a.add(AD_FLAGS, APP_AD_FLAGS)
        a.add(name_type, ad_name)
        a.add(AD_COMPLETE_LIST_16_BIT_SERVICE_UUIDS, BLETransport.u16_le(CSC_SERVICE_UUID))
        a.add(AD_APPEARANCE, appearance_payload)
      end
    end
  end
end

# BLE transport helpers for PicoRuby cycling sensors.
#
# BLETransport::Fake implements the same small surface as the PicoRuby adapter
# and is intended for host-side tests. BLETransport::PicoRubyPeripheral wraps
# PicoRuby's `picoruby-ble` gem when it is available on a Pico W/Pico 2 W
# firmware image.

begin
  require "ble"
rescue LoadError
end

module BLETransport
  READ = 0x02
  WRITE = 0x08
  NOTIFY = 0x10
  INDICATE = 0x20
  DYNAMIC = 0x100

  GATT_PRIMARY_SERVICE_UUID = 0x2800
  GAP_SERVICE_UUID = 0x1800
  GAP_DEVICE_NAME_UUID = 0x2A00
  CLIENT_CHARACTERISTIC_CONFIGURATION = 0x2902

  AD_FLAGS = 0x01
  AD_COMPLETE_LIST_16_BIT_SERVICE_UUIDS = 0x03
  AD_COMPLETE_LOCAL_NAME = 0x09
  APP_AD_FLAGS = 0x06

  module Bytes
    def self.binary_string
      str = String.new
      str = str.force_encoding("BINARY") if str.respond_to?(:force_encoding)
      str
    end

    def self.pack(*values)
      str = binary_string
      values.each do |value|
        str << (value & 0xff)
      end
      str
    end

    def self.u8(value)
      pack(value)
    end

    def self.u16_le(value)
      value &= 0xffff
      pack(value, value >> 8)
    end

    def self.s16_le(value)
      value += 0x10000 if value < 0
      u16_le(value)
    end

    def self.u32_le(value)
      value &= 0xffffffff
      pack(value, value >> 8, value >> 16, value >> 24)
    end

    def self.service_uuid16_list(uuids)
      str = binary_string
      uuids.each do |uuid|
        next unless uuid.is_a?(Integer) && uuid <= 0xffff
        str << u16_le(uuid)
      end
      str
    end
  end

  class Service
    attr_reader :uuid, :characteristics

    def initialize(uuid)
      @uuid = uuid
      @characteristics = []
    end
  end

  class Characteristic
    attr_reader :uuid, :properties, :permissions
    attr_accessor :value, :handle, :cccd_handle

    def initialize(service, uuid, properties, permissions, value = nil)
      @service = service
      @uuid = uuid
      @properties = properties
      @permissions = permissions
      @value = value || ""
      @handle = nil
      @cccd_handle = nil
      @write_callback = nil
    end

    def notifiable?
      (@properties & NOTIFY) != 0
    end

    def indicatable?
      (@properties & INDICATE) != 0
    end

    def on_write(&block)
      @write_callback = block
    end

    def call_write(bytes)
      @write_callback.call(bytes) if @write_callback
    end
  end

  class Fake
    attr_reader :name, :services, :advertising_services
    attr_reader :notifications, :indications, :writes

    def initialize
      @services = []
      @advertising = false
      @connected = true
      @notifications = []
      @indications = []
      @writes = []
      @next_handle = 1
    end

    def add_service(uuid)
      service = Service.new(uuid)
      @services << service
      service
    end

    def add_characteristic(service, uuid:, properties:, permissions:, value: nil)
      characteristic = Characteristic.new(service, uuid, properties, permissions, value)
      characteristic.handle = allocate_handle
      characteristic.cccd_handle = allocate_handle if (properties & (NOTIFY | INDICATE)) != 0
      service.characteristics << characteristic
      characteristic
    end

    def start_advertising(name:, services:, data: nil)
      @name = name
      @advertising_services = services
      @advertising_data = data
      @advertising = true
      true
    end

    def stop_advertising
      @advertising = false
      true
    end

    def advertising?
      @advertising
    end

    def connected?
      @connected
    end

    def connected=(value)
      @connected = !!value
    end

    def notify(characteristic, bytes)
      characteristic.value = bytes
      @notifications << {
        :uuid => characteristic.uuid,
        :handle => characteristic.handle,
        :bytes => bytes
      }
      true
    end

    def indicate(characteristic, bytes)
      characteristic.value = bytes
      @indications << {
        :uuid => characteristic.uuid,
        :handle => characteristic.handle,
        :bytes => bytes
      }
      true
    end

    def on_write(characteristic, &block)
      characteristic.on_write(&block)
    end

    def write(characteristic, bytes)
      @writes << {
        :uuid => characteristic.uuid,
        :handle => characteristic.handle,
        :bytes => bytes
      }
      characteristic.call_write(bytes)
    end

    private

    def allocate_handle
      handle = @next_handle
      @next_handle += 1
      handle
    end
  end

  if defined?(::BLE)
    class PicoRubyRuntime < ::BLE
      BTSTACK_EVENT_STATE = 0x60
      HCI_EVENT_DISCONNECTION_COMPLETE = 0x05
      ATT_EVENT_MTU_EXCHANGE_COMPLETE = 0xB5
      USER_BLOCK_CALL_COUNT_PER_POLL = 5

      def initialize(profile_data, adv_data, cccd_by_handle)
        @adv_data = adv_data
        @cccd_by_handle = cccd_by_handle
        @notification_enabled = {}
        @advertising_started = false
        @connected = false
        super(:peripheral, profile_data)
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

      def stop_advertising
        @advertising_started = false
        true
      end

      def notify_value(handle, bytes)
        return false unless @notification_enabled[handle]
        push_read_value(handle, bytes)
        notify(handle)
        true
      end

      def indicate_value(_handle, _bytes)
        raise "PicoRuby BLE indication is not exposed by picoruby-ble"
      end

      def start(timeout_ms = nil, &block)
        total_timeout_ms = 0
        hci_power_control(HCI_POWER_ON)
        while true
          break if timeout_ms && timeout_ms <= total_timeout_ms
          poll_once
          if block
            sub_sleep_ms = POLLING_UNIT_MS / USER_BLOCK_CALL_COUNT_PER_POLL
            i = 0
            while i < USER_BLOCK_CALL_COUNT_PER_POLL
              i += 1
              block.call
              sleep_ms sub_sleep_ms
              total_timeout_ms += sub_sleep_ms
              break if timeout_ms && timeout_ms <= total_timeout_ms
            end
          else
            sleep_ms POLLING_UNIT_MS
            total_timeout_ms += POLLING_UNIT_MS
          end
        end
        total_timeout_ms
      ensure
        hci_power_control(HCI_POWER_OFF)
        @ensure_proc&.call
      end

      def poll_once
        while (packet = pop_packet)
          packet_callback(packet)
        end
        while pop_heartbeat
          heartbeat_callback
        end
      end

      def heartbeat_callback
        blink_led
        check_cccd
      end

      def packet_callback(event_packet)
        case event_packet[0]&.ord
        when BTSTACK_EVENT_STATE
          start_advertising if event_packet[2]&.ord == HCI_STATE_WORKING
        when HCI_EVENT_DISCONNECTION_COMPLETE
          @connected = false
          @advertising_started = false
          @notification_enabled = {}
          start_advertising
        when ATT_EVENT_MTU_EXCHANGE_COMPLETE
          @connected = true
        end
      end

      private

      def check_cccd
        @cccd_by_handle.each do |value_handle, cccd_handle|
          while (data = pop_write_value(cccd_handle))
            @notification_enabled[value_handle] = (data == "\x01\x00")
          end
        end
      end
    end

    class PicoRubyPeripheral
      attr_reader :runtime, :services

      def initialize
        @services = []
        @runtime = nil
      end

      def add_service(uuid)
        service = Service.new(uuid)
        @services << service
        service
      end

      def add_characteristic(service, uuid:, properties:, permissions:, value: nil)
        characteristic = Characteristic.new(service, uuid, properties, permissions, value)
        service.characteristics << characteristic
        characteristic
      end

      def start_advertising(name:, services:, data: nil)
        db = build_database(name)
        adv_data = data || build_advertising_data(name, services)
        cccd_by_handle = {}

        @services.each do |service|
          service.characteristics.each do |characteristic|
            table = db.handle_table[service.uuid][characteristic.uuid]
            characteristic.handle = table[:value_handle]
            if (characteristic.properties & (NOTIFY | INDICATE)) != 0
              characteristic.cccd_handle = table[CLIENT_CHARACTERISTIC_CONFIGURATION]
              cccd_by_handle[characteristic.handle] = characteristic.cccd_handle
            end
          end
        end

        @runtime = PicoRubyRuntime.new(db.profile_data, adv_data, cccd_by_handle)
        true
      end

      def stop_advertising
        @runtime&.stop_advertising
      end

      def connected?
        @runtime && @runtime.connected?
      end

      def notify(characteristic, bytes)
        characteristic.value = bytes
        @runtime.notify_value(characteristic.handle, bytes)
      end

      def indicate(characteristic, bytes)
        characteristic.value = bytes
        @runtime.indicate_value(characteristic.handle, bytes)
      end

      def on_write(characteristic, &block)
        characteristic.on_write(&block)
      end

      def start(timeout_ms = nil, &block)
        raise "BLE runtime is not started" unless @runtime
        @runtime.start(timeout_ms, &block)
      end

      def poll
        raise "BLE runtime is not started" unless @runtime
        @runtime.poll_once
      end

      private

      def build_database(name)
        ::BLE::GattDatabase.new do |db|
          db.add_service(GATT_PRIMARY_SERVICE_UUID, GAP_SERVICE_UUID) do |s|
            s.add_characteristic(READ, GAP_DEVICE_NAME_UUID, READ, name)
          end

          @services.each do |service|
            db.add_service(GATT_PRIMARY_SERVICE_UUID, service.uuid) do |s|
              service.characteristics.each do |characteristic|
                props = characteristic.properties | DYNAMIC
                permissions = characteristic.permissions | DYNAMIC
                s.add_characteristic(props, characteristic.uuid, permissions, characteristic.value || "") do |c|
                  if (characteristic.properties & (NOTIFY | INDICATE)) != 0
                    c.add_descriptor(READ | WRITE | DYNAMIC, CLIENT_CHARACTERISTIC_CONFIGURATION, "\x00\x00")
                  end
                end
              end
            end
          end
        end
      end

      def build_advertising_data(name, services)
        ::BLE::AdvertisingData.build do |a|
          a.add(AD_FLAGS, APP_AD_FLAGS)
          a.add(AD_COMPLETE_LOCAL_NAME, name)
          a.add(AD_COMPLETE_LIST_16_BIT_SERVICE_UUIDS, Bytes.service_uuid16_list(services))
        end
      end
    end
  end
end

class BLE
  HCI_STATE_WORKING = 2
  HCI_POWER_ON = 1
  HCI_POWER_OFF = 0
  POLLING_UNIT_MS = 100
  WRITE_WITHOUT_RESPONSE = 4

  attr_reader :native_init, :native_update, :profile_data, :advertisements, :power_events
  attr_writer :native_measurement_status

  def initialize(_role, profile_data)
    @profile_data = profile_data
    @packets = []
    @advertisements = []
    @power_events = []
  end

  def csc_server_init(wheel, crank, sensor_location)
    @native_init = [wheel, crank, sensor_location]
  end

  def csc_server_update(wheel_delta, wheel_time, crank_delta, crank_time)
    @native_update = [wheel_delta, wheel_time, crank_delta, crank_time]
  end

  def csc_server_measurement_status
    @native_measurement_status || 0
  end

  def peripheral_advertise(data, min_interval, max_interval)
    @advertisements << [data, min_interval, max_interval]
  end

  def hci_power_control(mode)
    @power_events << mode
  end

  def queue_packet(packet)
    @packets << packet
  end

  def pop_packet
    @packets.shift
  end

  def pop_heartbeat
    false
  end

  def event_queue_dropped
    0
  end

  class GattDatabase
    class << self
      attr_accessor :last
    end

    attr_reader :handle_table, :profile_data, :characteristics

    def initialize
      self.class.last = self
      @handle_table = {}
      @profile_data = "\x01\x00\x00"
      @characteristics = []
      @service_uuid = nil
      @char_uuid = nil
      @next_handle = 0
      yield self
    end

    def add_service(_uuid, service_uuid)
      @service_uuid = service_uuid
      @handle_table[service_uuid] = {}
      yield self if block_given?
      @service_uuid = nil
    end

    def add_characteristic(properties, uuid, value_properties, value)
      @next_handle += 1
      record = {
        :service => @service_uuid,
        :uuid => uuid,
        :properties => properties,
        :value_properties => value_properties,
        :value => value,
        :descriptors => []
      }
      @characteristics << record
      @handle_table[@service_uuid][uuid] = { :value_handle => @next_handle }
      @char_uuid = uuid
      yield self if block_given?
      @char_uuid = nil
    end

    def add_descriptor(properties, uuid, value)
      @next_handle += 1
      record = @characteristics[-1]
      record[:descriptors] << [properties, uuid, value]
      @handle_table[@service_uuid][@char_uuid][uuid] = @next_handle
    end
  end

  class AdvertisingData
    class << self
      attr_accessor :last
    end

    def self.build
      builder = new
      self.last = builder
      yield builder
      builder.data
    end

    attr_reader :fields, :data

    def initialize
      @fields = []
      @data = String.new
    end

    def add(type, value)
      @fields << [type, value]
      @data << type
      @data << value
    end
  end
end

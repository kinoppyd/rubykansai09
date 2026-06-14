require "ble_transport"

class BLECSCService
  SERVICE_UUID = 0x1816
  CSC_MEASUREMENT_UUID = 0x2A5B
  CSC_FEATURE_UUID = 0x2A5C
  SENSOR_LOCATION_UUID = 0x2A5D

  BATTERY_SERVICE_UUID = 0x180F
  BATTERY_LEVEL_UUID = 0x2A19

  DEVICE_INFORMATION_SERVICE_UUID = 0x180A
  MANUFACTURER_NAME_UUID = 0x2A29
  MODEL_NUMBER_UUID = 0x2A24
  FIRMWARE_REVISION_UUID = 0x2A26

  FEATURE_WHEEL = 0x0001
  FEATURE_CRANK = 0x0002
  FEATURE_MULTIPLE_SENSOR_LOCATIONS = 0x0004

  SENSOR_LOCATIONS = {
    :other => 0,
    :top_of_shoe => 1,
    :in_shoe => 2,
    :hip => 3,
    :front_wheel => 4,
    :left_crank => 5,
    :right_crank => 6,
    :left_pedal => 7,
    :right_pedal => 8,
    :front_hub => 9,
    :rear_dropout => 10,
    :chainstay => 11,
    :rear_wheel => 12,
    :rear_hub => 13,
    :chest => 14
  }

  attr_reader :transport, :measurement_characteristic
  attr_reader :wheel_revolutions, :wheel_event_time
  attr_reader :crank_revolutions, :crank_event_time

  def initialize(transport:, name: "PicoRuby CSC", wheel: true, crank: true,
                 sensor_location: nil, multiple_sensor_locations: false,
                 notify_interval_ms: 1_000,
                 battery_level: nil,
                 manufacturer_name: nil,
                 model_number: nil,
                 firmware_revision: nil)
    @transport = transport
    @name = name
    @wheel_supported = !!wheel
    @crank_supported = !!crank
    @sensor_location = normalize_sensor_location(sensor_location)
    @multiple_sensor_locations = !!multiple_sensor_locations
    @notify_interval_ms = notify_interval_ms
    @battery_level = battery_level
    @manufacturer_name = manufacturer_name
    @model_number = model_number
    @firmware_revision = firmware_revision

    @wheel_revolutions = 0
    @wheel_event_time = 0
    @crank_revolutions = 0
    @crank_event_time = 0
    @last_notify_ms = nil
    @started = false
  end

  def start
    csc = @transport.add_service(SERVICE_UUID)
    @measurement_characteristic = @transport.add_characteristic(
      csc,
      :uuid => CSC_MEASUREMENT_UUID,
      :properties => BLETransport::NOTIFY,
      :permissions => BLETransport::NOTIFY,
      :value => ""
    )
    @feature_characteristic = @transport.add_characteristic(
      csc,
      :uuid => CSC_FEATURE_UUID,
      :properties => BLETransport::READ,
      :permissions => BLETransport::READ,
      :value => feature_payload
    )
    if @sensor_location
      @sensor_location_characteristic = @transport.add_characteristic(
        csc,
        :uuid => SENSOR_LOCATION_UUID,
        :properties => BLETransport::READ,
        :permissions => BLETransport::READ,
        :value => BLETransport::Bytes.u8(@sensor_location)
      )
    end

    add_battery_service if @battery_level
    add_device_information_service if @manufacturer_name || @model_number || @firmware_revision

    @transport.start_advertising(:name => @name, :services => advertised_services)
    @started = true
    true
  end

  def started?
    @started
  end

  def connected?
    @transport.connected?
  end

  def update_wheel(revolutions, time_ms)
    return false unless @wheel_supported
    @wheel_revolutions = clamp_u32(revolutions)
    @wheel_event_time = event_time_ticks(time_ms)
    true
  end

  def update_crank(revolutions, time_ms)
    return false unless @crank_supported
    @crank_revolutions = revolutions & 0xffff
    @crank_event_time = event_time_ticks(time_ms)
    true
  end

  def notify(now_ms = nil)
    raise "BLECSCService is not started" unless @started
    @last_notify_ms = now_ms
    @transport.notify(@measurement_characteristic, measurement_payload)
  end

  def notify_if_due(now_ms)
    return notify(now_ms) if @last_notify_ms.nil?
    return notify(now_ms) if @notify_interval_ms <= (now_ms - @last_notify_ms)
    false
  end

  def feature_value
    value = 0
    value |= FEATURE_WHEEL if @wheel_supported
    value |= FEATURE_CRANK if @crank_supported
    value |= FEATURE_MULTIPLE_SENSOR_LOCATIONS if @multiple_sensor_locations
    value
  end

  def feature_payload
    BLETransport::Bytes.u16_le(feature_value)
  end

  def measurement_payload
    flags = 0
    flags |= 0x01 if @wheel_supported
    flags |= 0x02 if @crank_supported

    payload = BLETransport::Bytes.u8(flags)
    if @wheel_supported
      payload << BLETransport::Bytes.u32_le(@wheel_revolutions)
      payload << BLETransport::Bytes.u16_le(@wheel_event_time)
    end
    if @crank_supported
      payload << BLETransport::Bytes.u16_le(@crank_revolutions)
      payload << BLETransport::Bytes.u16_le(@crank_event_time)
    end
    payload
  end

  def self.event_time_ticks(time_ms)
    ((time_ms.to_i * 1024) / 1000) & 0xffff
  end

  def event_time_ticks(time_ms)
    self.class.event_time_ticks(time_ms)
  end

  private

  def advertised_services
    services = [SERVICE_UUID]
    services << BATTERY_SERVICE_UUID if @battery_level
    services << DEVICE_INFORMATION_SERVICE_UUID if @manufacturer_name || @model_number || @firmware_revision
    services
  end

  def add_battery_service
    service = @transport.add_service(BATTERY_SERVICE_UUID)
    @battery_characteristic = @transport.add_characteristic(
      service,
      :uuid => BATTERY_LEVEL_UUID,
      :properties => BLETransport::READ | BLETransport::NOTIFY,
      :permissions => BLETransport::READ | BLETransport::NOTIFY,
      :value => BLETransport::Bytes.u8(clamp(@battery_level, 0, 100))
    )
  end

  def add_device_information_service
    service = @transport.add_service(DEVICE_INFORMATION_SERVICE_UUID)
    add_device_info_characteristic(service, MANUFACTURER_NAME_UUID, @manufacturer_name)
    add_device_info_characteristic(service, MODEL_NUMBER_UUID, @model_number)
    add_device_info_characteristic(service, FIRMWARE_REVISION_UUID, @firmware_revision)
  end

  def add_device_info_characteristic(service, uuid, value)
    return unless value
    @transport.add_characteristic(
      service,
      :uuid => uuid,
      :properties => BLETransport::READ,
      :permissions => BLETransport::READ,
      :value => value.to_s
    )
  end

  def normalize_sensor_location(location)
    return nil if location.nil?
    return location if location.is_a?(Integer)
    SENSOR_LOCATIONS[location.to_sym] || raise(ArgumentError, "unknown sensor location: #{location}")
  end

  def clamp_u32(value)
    value = value.to_i
    return 0 if value < 0
    value & 0xffffffff
  end

  def clamp(value, min, max)
    value = value.to_i
    return min if value < min
    return max if value > max
    value
  end
end

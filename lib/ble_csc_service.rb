# Usage:
#   require "ble_transport/picoruby_peripheral"
#   require "ble_csc_service"
#   ble = BLETransport::PicoRubyPeripheral.new
#   service = BLECSCService.new(ble, "PicoRuby CSC", true, true)
#   service.start
#   service.update_wheel(wheel_count, time_ms)
#   service.update_crank(crank_count, time_ms)
#   service.notify_if_due(time_ms)
#
# Builds Bluetooth Cycling Speed and Cadence measurement payloads. The
# transport object must implement setup_csc, notify, connected?, and poll.

require "ble_transport"

class BLECSCService
  SERVICE_UUID = BLETransport::CSC_SERVICE_UUID
  CSC_MEASUREMENT_UUID = BLETransport::CSC_MEASUREMENT_UUID
  CSC_FEATURE_UUID = BLETransport::CSC_FEATURE_UUID
  SENSOR_LOCATION_UUID = BLETransport::CSC_SENSOR_LOCATION_UUID

  FEATURE_WHEEL = 1
  FEATURE_CRANK = 2
  MAX_WHEEL_REVOLUTIONS = 0xffffffff

  def initialize(transport, name = "PicoRuby CSC", wheel = true, crank = true, sensor_location = nil, notify_interval_ms = 1000)
    @transport = transport
    @name = name
    @wheel_supported = !!wheel
    @crank_supported = !!crank
    @sensor_location = sensor_location
    @notify_interval_ms = notify_interval_ms

    @wheel_revolutions = 0
    @wheel_event_time = 0
    @crank_revolutions = 0
    @crank_event_time = 0
    @last_notify_ms = nil
    @started = false
    @native_transport = @transport.respond_to?(:notify_csc)

    @flags = 0
    @flags |= 1 if @wheel_supported
    @flags |= 2 if @crank_supported
    @feature_value = 0
    @feature_value |= FEATURE_WHEEL if @wheel_supported
    @feature_value |= FEATURE_CRANK if @crank_supported
    @feature_payload = BLETransport.bytes(2)
    BLETransport.put_u16(@feature_payload, 0, @feature_value)

    @payload_size = 1
    @payload_size += 6 if @wheel_supported
    @payload_size += 4 if @crank_supported
    @payload = @native_transport ? nil : BLETransport.bytes(@payload_size)
  end

  def start
    @measurement_characteristic = @transport.setup_csc(@name, @feature_payload, @sensor_location)
    @started = true
    true
  end

  def started?
    @started
  end

  def connected?
    @transport.connected?
  end

  def measurement_characteristic
    @measurement_characteristic
  end

  def wheel_revolutions
    @wheel_revolutions
  end

  def wheel_event_time
    @wheel_event_time
  end

  def crank_revolutions
    @crank_revolutions
  end

  def crank_event_time
    @crank_event_time
  end

  def update_wheel(revolutions, time_ms)
    return false unless @wheel_supported
    @wheel_revolutions = revolutions
    @wheel_revolutions = 0 if @wheel_revolutions < 0
    @wheel_revolutions = MAX_WHEEL_REVOLUTIONS if MAX_WHEEL_REVOLUTIONS < @wheel_revolutions
    @wheel_event_time = event_time_ticks(time_ms)
    true
  end

  def update_crank(revolutions, time_ms)
    return false unless @crank_supported
    @crank_revolutions = revolutions & 0xffff
    @crank_event_time = event_time_ticks(time_ms)
    true
  end

  def add_wheel(revolutions, time_ms)
    return false unless @wheel_supported
    update_wheel(@wheel_revolutions + revolutions, time_ms)
  end

  def add_crank(revolutions, time_ms)
    return false unless @crank_supported
    update_crank(@crank_revolutions + revolutions, time_ms)
  end

  def notify(now_ms = nil)
    @last_notify_ms = now_ms
    if @native_transport
      @transport.notify_csc(
        @wheel_revolutions,
        @wheel_event_time,
        @crank_revolutions,
        @crank_event_time
      )
    else
      @transport.notify(@measurement_characteristic, measurement_payload)
    end
  end

  def notify_if_due(now_ms)
    return notify(now_ms) if @last_notify_ms.nil?
    elapsed = (now_ms - @last_notify_ms) & 0xffffffff
    return notify(now_ms) if @notify_interval_ms <= elapsed
    false
  end

  def feature_value
    @feature_value
  end

  def feature_payload
    @feature_payload
  end

  def measurement_payload
    @payload = BLETransport.bytes(@payload_size) if @payload.nil?
    i = 1
    BLETransport.put_u8(@payload, 0, @flags)

    if @wheel_supported
      BLETransport.put_u32(@payload, i, @wheel_revolutions)
      i += 4
      BLETransport.put_u16(@payload, i, @wheel_event_time)
      i += 2
    end

    if @crank_supported
      BLETransport.put_u16(@payload, i, @crank_revolutions)
      i += 2
      BLETransport.put_u16(@payload, i, @crank_event_time)
    end

    @payload
  end

  def self.event_time_ticks(time_ms)
    ((time_ms * 1024) / 1000) & 0xffff
  end

  def event_time_ticks(time_ms)
    ((time_ms * 1024) / 1000) & 0xffff
  end
end

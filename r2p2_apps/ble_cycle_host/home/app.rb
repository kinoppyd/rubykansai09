# BLE cycle host app for R2P2/PicoRuby on Raspberry Pi Pico 2 W.
# It receives dedicated speed/cadence BLE::UART sensors and drives two meters.

require "machine"
require "ble_cycle_packet"
require "ble_cycle_host/multi_uart_central"
require "ble_cycle_host/speed_estimator"
require "ble_cycle_host/cadence_estimator"
require "ble_cycle_host/display_output"

DEBUG_BLE = true
DEBUG_RX = true
DEBUG_STATUS = true
DEBUG_DISPLAY = true
SPEED_DEVICE_NAME = "PRCycle"
SPEED_DEVICE_ADDRESS = "88:A2:9E:0B:A7:DE"
CADENCE_DEVICE_NAME = "PRCad"
# Set the PRCad address after bring-up. nil uses the short GAP name temporarily.
CADENCE_DEVICE_ADDRESS = nil
WHEEL_CIRCUMFERENCE_MM = 2105
SCAN_STATUS_PERIOD_MS = 5000
RX_TIMEOUT_MS = 1500
DISPLAY_MODE = :dual_gc9a01 # :none, :uart, :gc9a01, or :dual_gc9a01
DISPLAY_PERIOD_MS = 100
DISPLAY_UART_UNIT = :RP2040_UART0
DISPLAY_UART_TXD_PIN = 0
DISPLAY_UART_RXD_PIN = 1
DISPLAY_UART_BAUDRATE = 115_200
DISPLAY_GC9A01_SPI_HOST = 0
DISPLAY_GC9A01_PIN_SCLK = 18
DISPLAY_GC9A01_PIN_MOSI = 19
DISPLAY_GC9A01_PIN_CS = 17
DISPLAY_GC9A01_PIN_DC = 20
DISPLAY_GC9A01_PIN_RST = 21
DISPLAY_GC9A01_PIN_BL = 22
DISPLAY_GC9A01_SPI_FREQUENCY = 40_000_000
DISPLAY_GC9A01_BRIGHTNESS = 180
DISPLAY_CADENCE_SPI_HOST = 1
DISPLAY_CADENCE_PIN_SCLK = 10
DISPLAY_CADENCE_PIN_MOSI = 11
DISPLAY_CADENCE_PIN_CS = 9
DISPLAY_CADENCE_PIN_DC = 12
DISPLAY_CADENCE_PIN_RST = 13
DISPLAY_CADENCE_PIN_BL = 14
DISPLAY_CADENCE_SPI_FREQUENCY = 40_000_000
DISPLAY_CADENCE_BRIGHTNESS = 180
DISPLAY_STARTUP_SWEEP_MAX_KMH = 80
DISPLAY_STARTUP_SWEEP_MAX_CADENCE_RPM = 120
DISPLAY_STARTUP_SWEEP_STEP_KMH = 4
DISPLAY_STARTUP_SWEEP_FRAME_MS = 20
DISPLAY_STARTUP_SWEEP_PAUSE_MS = 250

def rounded_2(v)
  (v * 100.0).to_i / 100.0
end

def now_ms
  if Object.const_defined?(:Machine)
    return Machine.uptime_us / 1000 if Machine.respond_to?(:uptime_us)
    return Machine.board_millis if Machine.respond_to?(:board_millis)
  end
  0
end

def display_due?(now, last)
  last.nil? || ((now - last) & 0xffffffff) >= DISPLAY_PERIOD_MS
end

def display_status(central, speed_timed_out, cadence_timed_out,
                   speed_sensor_error, cadence_sensor_error)
  status = central.connected? ? BLECycleHost::DisplayStatus::BLE_CONNECTED : 0
  if speed_timed_out || cadence_timed_out
    status |= BLECycleHost::DisplayStatus::STALE
  end
  if central.speed_slot.reader.last_gap != 0 ||
     central.cadence_slot.reader.last_gap != 0
    status |= BLECycleHost::DisplayStatus::SEQUENCE_GAP
  end
  if speed_sensor_error || cadence_sensor_error
    status |= BLECycleHost::DisplayStatus::SENSOR_ERROR
  end
  status
end

def build_display_output
  case DISPLAY_MODE
  when :uart
    require "uart"
    uart = UART.new(
      unit: DISPLAY_UART_UNIT,
      txd_pin: DISPLAY_UART_TXD_PIN,
      rxd_pin: DISPLAY_UART_RXD_PIN,
      baudrate: DISPLAY_UART_BAUDRATE
    )
    puts "display_link"
    puts "uart"
    BLECycleHost::UARTDisplayOutput.new(uart)
  when :gc9a01, :dual_gc9a01
    require "gc9a01_speedometer"
    GC9A01Display.configure(
      DISPLAY_GC9A01_SPI_HOST,
      DISPLAY_GC9A01_PIN_SCLK,
      DISPLAY_GC9A01_PIN_MOSI,
      DISPLAY_GC9A01_PIN_CS,
      DISPLAY_GC9A01_PIN_DC,
      DISPLAY_GC9A01_PIN_RST,
      DISPLAY_GC9A01_PIN_BL,
      DISPLAY_GC9A01_SPI_FREQUENCY
    )
    cadence_meter = nil
    if DISPLAY_MODE == :dual_gc9a01
      GC9A01Display.configure_secondary(
        DISPLAY_CADENCE_SPI_HOST,
        DISPLAY_CADENCE_PIN_SCLK,
        DISPLAY_CADENCE_PIN_MOSI,
        DISPLAY_CADENCE_PIN_CS,
        DISPLAY_CADENCE_PIN_DC,
        DISPLAY_CADENCE_PIN_RST,
        DISPLAY_CADENCE_PIN_BL,
        DISPLAY_CADENCE_SPI_FREQUENCY
      )
      cadence_meter = GC9A01Speedometer.new(GC9A01Display::SECONDARY)
      cadence_meter.brightness = DISPLAY_CADENCE_BRIGHTNESS
    end
    meter = GC9A01SimpleSpeedometer.new(GC9A01Display::PRIMARY)
    meter.brightness = DISPLAY_GC9A01_BRIGHTNESS
    puts "display_link"
    puts(DISPLAY_MODE == :dual_gc9a01 ? "dual_gc9a01" : "gc9a01")
    BLECycleHost::GC9A01DisplayOutput.new(meter, cadence_meter)
  else
    BLECycleHost::NullDisplayOutput.new
  end
end

def write_display(output, speed_kmh, cadence_rpm, status, now)
  return false unless output.active?
  output.write(speed_kmh, status, cadence_rpm)
  if DEBUG_DISPLAY
    puts "display_tx"
    puts "seq"
    puts output.last_sequence
    puts "speed_kmh"
    puts rounded_2(speed_kmh)
    puts "cadence_rpm"
    puts rounded_2(cadence_rpm)
    puts "status"
    puts status
  end
  now
end

def run_display_startup_sweep(output)
  return false unless output.active?

  puts "display_startup_sweep"
  puts "start"
  Machine.delay_ms(DISPLAY_STARTUP_SWEEP_PAUSE_MS)
  BLECycleHost::DisplayAnimation.startup_sweep(
    output,
    DISPLAY_STARTUP_SWEEP_MAX_KMH,
    DISPLAY_STARTUP_SWEEP_STEP_KMH,
    DISPLAY_STARTUP_SWEEP_MAX_CADENCE_RPM
  ) do
    Machine.delay_ms(DISPLAY_STARTUP_SWEEP_FRAME_MS)
  end
  puts "display_startup_sweep"
  puts "done"
  true
end

puts "BLE cycle host"
puts "wheel_circumference_mm"
puts WHEEL_CIRCUMFERENCE_MM
puts "speed_target_name"
puts SPEED_DEVICE_NAME
puts "speed_target_address"
puts SPEED_DEVICE_ADDRESS
puts "cadence_target_name"
puts CADENCE_DEVICE_NAME
puts "cadence_target_address"
puts(CADENCE_DEVICE_ADDRESS || "name_fallback")

display_output = build_display_output
run_display_startup_sweep(display_output)
speed_estimator = BLECycleHost::SpeedEstimator.new(WHEEL_CIRCUMFERENCE_MM, RX_TIMEOUT_MS)
cadence_estimator = BLECycleHost::CadenceEstimator.new(RX_TIMEOUT_MS)
central = BLECycleHost::MultiUARTCentral.new(
  speed_address: SPEED_DEVICE_ADDRESS,
  cadence_address: CADENCE_DEVICE_ADDRESS,
  speed_name: SPEED_DEVICE_NAME,
  cadence_name: CADENCE_DEVICE_NAME
)
central.debug = DEBUG_BLE
speed_rx_count = 0
cadence_rx_count = 0
last_speed_ready = false
last_cadence_ready = false
last_status_ms = nil
last_display_ms = nil
speed_timed_out = true
cadence_timed_out = true
speed_sensor_error = false
cadence_sensor_error = false

central.start do |role, packet, reader|
  now = now_ms
  force_display = false

  speed_ready = central.speed_ready?
  if speed_ready != last_speed_ready
    puts "ble_slot"
    puts "speed"
    puts "slot_state"
    puts central.slot_state(:speed)
    puts "connection_handle"
    puts(central.speed_slot.connection_handle || -1)
    unless speed_ready
      speed_estimator.stop!
      speed_timed_out = true
      speed_sensor_error = false
      force_display = true
    end
    last_speed_ready = speed_ready
  end

  cadence_ready = central.cadence_ready?
  if cadence_ready != last_cadence_ready
    puts "ble_slot"
    puts "cadence"
    puts "slot_state"
    puts central.slot_state(:cadence)
    puts "connection_handle"
    puts(central.cadence_slot.connection_handle || -1)
    unless cadence_ready
      cadence_estimator.stop!
      cadence_timed_out = true
      cadence_sensor_error = false
      force_display = true
    end
    last_cadence_ready = cadence_ready
  end

  if DEBUG_STATUS && !central.all_ready?
    elapsed = last_status_ms ? ((now - last_status_ms) & 0xffffffff) : SCAN_STATUS_PERIOD_MS
    if elapsed >= SCAN_STATUS_PERIOD_MS
      puts "scan_state"
      puts central.state
      puts "scan_reports"
      puts central.scan_report_count
      puts "ready_count"
      puts central.ready_count
      puts "speed_state"
      puts central.slot_state(:speed)
      puts "cadence_state"
      puts central.slot_state(:cadence)
      last_status_ms = now
    end
  end

  if speed_estimator.tick(now)
    puts "timeout_role"
    puts "speed"
    speed_timed_out = true
    force_display = true
  end

  if cadence_estimator.tick(now)
    puts "timeout_role"
    puts "cadence"
    cadence_timed_out = true
    force_display = true
  end

  if packet
    if role == :speed
      speed_rx_count += 1
      speed_estimator.update(packet, now)
      speed_timed_out = false
      speed_sensor_error = (packet.flags & BLECyclePacket::FLAG_I2C_ERROR) != 0
      rx_count = speed_rx_count
      slot = central.speed_slot
    elsif role == :cadence
      cadence_rx_count += 1
      cadence_estimator.update(packet, now)
      cadence_timed_out = false
      cadence_sensor_error = (packet.flags & BLECyclePacket::FLAG_I2C_ERROR) != 0
      rx_count = cadence_rx_count
      slot = central.cadence_slot
    end

    if DEBUG_RX && slot
      puts "RX"
      puts "role"
      puts role
      puts "count"
      puts rx_count
      puts "connection_handle"
      puts(slot.connection_handle || -1)
      puts "slot_state"
      puts slot.state
      puts "seq"
      puts packet.sequence
      puts "sensor_time_ms"
      puts packet.sensor_time_ms
      puts "total_rev"
      puts packet.total_revolutions
      puts "delta_mrad"
      puts packet.delta_angle_mrad
      puts "interval_ms"
      puts packet.interval_ms
      puts "flags"
      puts packet.flags
      puts "status"
      puts packet.status
      puts "speed_kmh"
      puts rounded_2(speed_estimator.speed_kmh)
      puts "cadence_rpm"
      puts rounded_2(cadence_estimator.cadence_rpm)
      puts "reader_gap"
      puts reader.last_gap
      puts "reader_gap_count"
      puts reader.gap_count
      puts "reader_dropped"
      puts reader.dropped_bytes
    end
  end

  if (packet || force_display) &&
     (force_display || display_due?(now, last_display_ms))
    status = display_status(
      central,
      speed_timed_out,
      cadence_timed_out,
      speed_sensor_error,
      cadence_sensor_error
    )
    sent_at = write_display(
      display_output,
      speed_estimator.speed_kmh,
      cadence_estimator.cadence_rpm,
      status,
      now
    )
    last_display_ms = sent_at if sent_at
  end
end

# BLE cycle host app for R2P2/PicoRuby on Raspberry Pi Pico 2 W.
# It receives custom BLE::UART frames and prints decoded speed values.

require "machine"
require "ble_cycle_packet"
require "ble_cycle_host/uart_central"
require "ble_cycle_host/speed_estimator"
require "ble_cycle_host/display_output"

DEBUG_BLE = true
DEBUG_DISPLAY = true
DEVICE_NAME = "PRCycle"
DEVICE_ADDRESS = "88:A2:9E:0B:A7:DE"
WHEEL_CIRCUMFERENCE_MM = 2105
SCAN_STATUS_PERIOD_MS = 5000
RX_TIMEOUT_MS = 1500
DISPLAY_MODE = :gc9a01 # :none, :uart, or :gc9a01
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
DISPLAY_STARTUP_SWEEP_MAX_KMH = 80
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

def display_status(connected, packet, reader)
  status = connected ? BLECycleHost::DisplayStatus::BLE_CONNECTED : 0
  status |= BLECycleHost::DisplayStatus::SEQUENCE_GAP if reader.last_gap != 0
  if packet && (packet.flags & BLECyclePacket::FLAG_I2C_ERROR) != 0
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
  when :gc9a01
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
    meter = GC9A01SimpleSpeedometer.new
    meter.brightness = DISPLAY_GC9A01_BRIGHTNESS
    puts "display_link"
    puts "gc9a01"
    BLECycleHost::GC9A01DisplayOutput.new(meter)
  else
    BLECycleHost::NullDisplayOutput.new
  end
end

def write_display(output, speed_kmh, status, now)
  return false unless output.active?
  output.write(speed_kmh, status)
  if DEBUG_DISPLAY
    puts "display_tx"
    puts "seq"
    puts output.last_sequence
    puts "speed_kmh"
    puts rounded_2(speed_kmh)
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
    DISPLAY_STARTUP_SWEEP_STEP_KMH
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
puts "target_name"
puts DEVICE_NAME
puts "target_address"
puts DEVICE_ADDRESS

display_output = build_display_output
run_display_startup_sweep(display_output)
estimator = BLECycleHost::SpeedEstimator.new(WHEEL_CIRCUMFERENCE_MM, RX_TIMEOUT_MS)
central = BLECycleHost::UARTCentral.new(DEVICE_NAME, DEVICE_ADDRESS)
central.debug = DEBUG_BLE
central.scan_debug = DEBUG_BLE
rx_count = 0
last_connected = false
last_status_ms = nil
last_display_ms = nil

central.start do |packet, reader|
  now = now_ms
  connected = central.connected?
  if connected != last_connected
    puts "ble_connected"
    puts(connected ? 1 : 0)
    last_connected = connected
  end

  if !connected
    elapsed = last_status_ms ? ((now - last_status_ms) & 0xffffffff) : SCAN_STATUS_PERIOD_MS
    if elapsed >= SCAN_STATUS_PERIOD_MS
      puts "scan_state"
      puts central.state
      puts "scan_reports"
      puts central.scan_reports
      last_status_ms = now
    end
  end

  unless packet
    if connected && estimator.tick(now)
      puts "speed_timeout"
      puts "speed_kmh"
      puts rounded_2(estimator.speed_kmh)
      sent_at = write_display(
        display_output,
        estimator.speed_kmh,
        BLECycleHost::DisplayStatus::BLE_CONNECTED | BLECycleHost::DisplayStatus::STALE,
        now
      )
      last_display_ms = sent_at if sent_at
    end
    next
  end

  rx_count += 1
  estimator.update(packet, now)
  display_status_value = display_status(connected, packet, reader)

  puts "RX"
  puts "count"
  puts rx_count
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
  puts rounded_2(estimator.speed_kmh)
  puts "cadence_rpm"
  puts rounded_2(estimator.cadence_rpm)
  puts "reader_gap"
  puts reader.last_gap
  puts "reader_gap_count"
  puts reader.gap_count
  puts "reader_dropped"
  puts reader.dropped_bytes

  if display_due?(now, last_display_ms)
    sent_at = write_display(
      display_output,
      estimator.speed_kmh,
      display_status_value,
      now
    )
    last_display_ms = sent_at if sent_at
  end
end

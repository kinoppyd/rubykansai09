# BLE cycle host app for R2P2/PicoRuby on Raspberry Pi Pico 2 W.
# It receives custom BLE::UART frames and prints decoded speed values.

require "machine"
require "ble_cycle_packet"
require "ble_cycle_host/uart_central"
require "ble_cycle_host/speed_estimator"

DEBUG_BLE = true
DEVICE_NAME = "PRCycle"
DEVICE_ADDRESS = "88:A2:9E:0B:A7:DE"
WHEEL_CIRCUMFERENCE_MM = 2105
SCAN_STATUS_PERIOD_MS = 5000
RX_TIMEOUT_MS = 1500

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

puts "BLE cycle host"
puts "wheel_circumference_mm"
puts WHEEL_CIRCUMFERENCE_MM
puts "target_name"
puts DEVICE_NAME
puts "target_address"
puts DEVICE_ADDRESS

central = BLECycleHost::UARTCentral.new(DEVICE_NAME, DEVICE_ADDRESS)
central.debug = DEBUG_BLE
central.scan_debug = DEBUG_BLE
estimator = BLECycleHost::SpeedEstimator.new(WHEEL_CIRCUMFERENCE_MM, RX_TIMEOUT_MS)
rx_count = 0
last_connected = false
last_status_ms = nil

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
    end
    next
  end

  rx_count += 1
  estimator.update(packet, now)

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
end

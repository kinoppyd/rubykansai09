# BLE cycle host app for R2P2/PicoRuby on Raspberry Pi Pico 2 W.
# It receives custom BLE::UART frames and prints decoded speed values.

require "ble_cycle_packet"
require "ble_cycle_host/uart_central"
require "ble_cycle_host/speed_estimator"

DEBUG_BLE = true
WHEEL_CIRCUMFERENCE_MM = 2105

def rounded_2(v)
  (v * 100.0).to_i / 100.0
end

puts "BLE cycle host"
puts "wheel_circumference_mm"
puts WHEEL_CIRCUMFERENCE_MM

central = BLECycleHost::UARTCentral.new
central.debug = DEBUG_BLE
estimator = BLECycleHost::SpeedEstimator.new(WHEEL_CIRCUMFERENCE_MM)
rx_count = 0

central.start do |packet, reader|
  rx_count += 1
  estimator.update(packet)

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

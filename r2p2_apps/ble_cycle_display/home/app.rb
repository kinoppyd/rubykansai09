# BLE cycle display app for R2P2/PicoRuby on Raspberry Pi Pico 2 W.
# Use this app only in the 3-board layout. The host sends display frames by UART.

require "machine"
require "uart"
require "gc9a01_speedometer"
require "ble_cycle_display_packet"

DEBUG_LOG = true

UART_UNIT = :RP2040_UART0
UART_TXD_PIN = 0
UART_RXD_PIN = 1
UART_BAUDRATE = 115_200
UART_RX_BUFFER_SIZE = 64

GC9A01_SPI_HOST = 0
GC9A01_PIN_SCLK = 18
GC9A01_PIN_MOSI = 19
GC9A01_PIN_CS = 17
GC9A01_PIN_DC = 20
GC9A01_PIN_RST = 21
GC9A01_PIN_BL = 22
GC9A01_SPI_FREQUENCY = 40_000_000
GC9A01_BRIGHTNESS = 180

DISPLAY_TIMEOUT_MS = 1500
POLL_DELAY_MS = 10

def now_ms
  if Object.const_defined?(:Machine)
    return Machine.uptime_us / 1000 if Machine.respond_to?(:uptime_us)
    return Machine.board_millis if Machine.respond_to?(:board_millis)
  end
  0
end

def rounded_2(v)
  (v * 100.0).to_i / 100.0
end

puts "BLE cycle display"
puts "display_link"
puts "uart"
puts "uart_unit"
puts UART_UNIT
puts "uart_baudrate"
puts UART_BAUDRATE

GC9A01Display.configure(
  GC9A01_SPI_HOST,
  GC9A01_PIN_SCLK,
  GC9A01_PIN_MOSI,
  GC9A01_PIN_CS,
  GC9A01_PIN_DC,
  GC9A01_PIN_RST,
  GC9A01_PIN_BL,
  GC9A01_SPI_FREQUENCY
)

meter = GC9A01SimpleSpeedometer.new
meter.brightness = GC9A01_BRIGHTNESS
meter.render(0.0)

uart = UART.new(
  unit: UART_UNIT,
  txd_pin: UART_TXD_PIN,
  rxd_pin: UART_RXD_PIN,
  baudrate: UART_BAUDRATE,
  rx_buffer_size: UART_RX_BUFFER_SIZE
)

reader = BLECycleDisplayPacket::FrameReader.new
packet = BLECycleDisplayPacket::Decoded.new
last_rx_ms = nil
last_speed_centi = 0
rx_count = 0
timed_out = false

loop do
  available = uart.bytes_available
  if available && available > 0
    data = uart.readpartial(32)
    reader.push(data) if data

    while reader.read(packet)
      now = now_ms
      rx_count += 1
      last_rx_ms = now
      timed_out = false

      if packet.speed_centi_kmh != last_speed_centi
        meter.render(BLECycleDisplayPacket.centi_kmh_to_speed(packet.speed_centi_kmh))
        last_speed_centi = packet.speed_centi_kmh
      end

      if DEBUG_LOG
        puts "DISPLAY_RX"
        puts "count"
        puts rx_count
        puts "seq"
        puts packet.sequence
        puts "speed_kmh"
        puts rounded_2(BLECycleDisplayPacket.centi_kmh_to_speed(packet.speed_centi_kmh))
        puts "status"
        puts packet.status
        puts "dropped"
        puts reader.dropped_bytes
      end
    end
  end

  if last_rx_ms && !timed_out
    elapsed = (now_ms - last_rx_ms) & 0xffffffff
    if elapsed >= DISPLAY_TIMEOUT_MS
      meter.render(0.0)
      last_speed_centi = 0
      timed_out = true
      puts "display_timeout"
    end
  end

  Machine.delay_ms(POLL_DELAY_MS)
end

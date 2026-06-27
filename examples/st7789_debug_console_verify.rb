# Usage:
#   Copy this file with lib/st7789_debug_console.rb to R2P2.
#   Update the pin constants below for your 240x240 ST7789 module.
#   Run it from irb or as an R2P2 app.

require "spi"
require "gpio"
require "st7789_debug_console"

SPI_UNIT = :RP2040_SPI0
SCK_PIN = 18
COPI_PIN = 19
CIPO_PIN = -1
CS_PIN = 17
DC_PIN = 20
RST_PIN = 21
BL_PIN = 22

SPI_FREQUENCY = 24_000_000
LCD_WIDTH = 240
LCD_HEIGHT = 240
X_OFFSET = 0
Y_OFFSET = 0
# Waveshare 1.3inch LCD Module uses this horizontal scan setting.
MADCTL = 0x70
INVERT = true

def wait_ms(ms)
  if Object.const_defined?(:Machine) && Machine.respond_to?(:delay_ms)
    Machine.delay_ms(ms)
  else
    sleep_ms ms
  end
end

spi = SPI.new(
  unit: SPI_UNIT,
  frequency: SPI_FREQUENCY,
  sck_pin: SCK_PIN,
  cipo_pin: CIPO_PIN,
  copi_pin: COPI_PIN,
  cs_pin: CS_PIN,
  mode: 0
)

dc = GPIO.new(DC_PIN, GPIO::OUT)
rst = GPIO.new(RST_PIN, GPIO::OUT)
bl = GPIO.new(BL_PIN, GPIO::OUT)

lcd = ST7789DebugConsole.new(
  spi,
  dc,
  rst,
  bl,
  :width => LCD_WIDTH,
  :height => LCD_HEIGHT,
  :x_offset => X_OFFSET,
  :y_offset => Y_OFFSET,
  :madctl => MADCTL,
  :invert => INVERT,
  :scroll_mode => :wrap,
  :foreground => ST7789DebugConsole::GREEN,
  :background => ST7789DebugConsole::BLACK
)

lcd.write_line("ST7789 debug")
lcd.write_line("240x240 RGB565")
lcd.write_line("PicoRuby")
lcd.write_line("lines: #{lcd.rows}")
lcd.write_line("cols: #{lcd.cols}")

i = 0
loop do
  lcd.write_line("counter #{i}")
  i += 1
  wait_ms 1000
end

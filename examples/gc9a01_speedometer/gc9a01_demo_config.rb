# Usage:
#   require 'gc9a01_demo_config'
#   GC9A01DemoConfig.apply
#
# Compile and install this file in R2P2's /lib together with the demo script.
# Change hardware and shared animation settings here instead of in each demo.

require 'gc9a01_speedometer'

module GC9A01DemoConfig
  SPI_HOST = 0
  PIN_SCLK = 18
  PIN_MOSI = 19
  PIN_CS = 17
  PIN_DC = 20
  PIN_RST = 21
  PIN_BL = 22
  SPI_FREQUENCY = 40_000_000

  BRIGHTNESS = 180
  FRAME_MS = 33
  SWEEP_DELAY_MS = 8
  SWEEP_PAUSE_MS = 250

  SPEED_MAX = 80
  SPEED_SWEEP_STEP = 4
  RPM_MAX = 180
  RPM_SWEEP_STEP = 9
  RIDING_MAX_SPEED = 75.0

  def self.apply
    GC9A01Display.configure(
      SPI_HOST,
      PIN_SCLK,
      PIN_MOSI,
      PIN_CS,
      PIN_DC,
      PIN_RST,
      PIN_BL,
      SPI_FREQUENCY
    )
  end
end

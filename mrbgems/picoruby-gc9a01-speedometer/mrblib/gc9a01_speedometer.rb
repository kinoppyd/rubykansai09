# Usage:
#   # Configure once, before creating either meter. This call is optional;
#   # omitted values use SPI0 and GPIO 18/19/17/20/21/22.
#   GC9A01Display.configure(0, 18, 19, 17, 20, 21, 22, 40_000_000)
#
#   # This class is built into the custom R2P2 firmware; require is unnecessary.
#   meter = GC9A01Speedometer.new
#   meter.render(28.4, 92) # Digital speed in km/h, analog cadence in rpm.
#   meter.brightness = 180 # Backlight brightness: 0..255.
#
#   # Render the built-in speed and cadence sweep animation.
#   meter.demo
#
# GC9A01Speedometer#demo blocks the current task. Use #demo_step from an
# existing application loop when sensor acquisition must run in the same task.

class GC9A01Display
  PRIMARY = 0
  SECONDARY = 1

  def self.configure(spi_host, sclk, mosi, cs, dc, rst, bl, frequency)
    _configure(PRIMARY, spi_host, sclk, mosi, cs, dc, rst, bl, frequency)
  end

  def self.configure_secondary(spi_host, sclk, mosi, cs, dc, rst, bl, frequency)
    _configure(SECONDARY, spi_host, sclk, mosi, cs, dc, rst, bl, frequency)
  end
end

class GC9A01Speedometer
  def initialize(display_index = GC9A01Display::PRIMARY)
    @display_index = display_index
    _init(@display_index)
  end

  def render(speed_kmh, cadence_rpm)
    _render(@display_index, speed_kmh, cadence_rpm)
  end

  def demo_step
    _demo_step(@display_index)
  end

  def brightness=(value)
    _set_brightness(@display_index, value)
  end

  def initialized?
    _initialized(@display_index)
  end

  def demo(frame_ms = 33)
    frame_ms = 1 if frame_ms < 1
    loop do
      demo_step
      Machine.delay_ms(frame_ms)
    end
  end
end

# Usage:
#   meter = GC9A01SimpleSpeedometer.new
#   meter.render(32.5)     # Analog speed: 0..80 km/h.
#   meter.brightness = 180 # Backlight brightness: 0..255.
#
#   # Render the built-in 0..80 km/h sweep animation.
#   meter.demo

class GC9A01SimpleSpeedometer
  def initialize(display_index = GC9A01Display::PRIMARY)
    @display_index = display_index
    _init(@display_index)
  end

  def render(speed_kmh)
    _render(@display_index, speed_kmh)
  end

  def demo_step
    _demo_step(@display_index)
  end

  def brightness=(value)
    _set_brightness(@display_index, value)
  end

  def initialized?
    _initialized(@display_index)
  end

  def demo(frame_ms = 33)
    frame_ms = 1 if frame_ms < 1
    loop do
      demo_step
      Machine.delay_ms(frame_ms)
    end
  end
end

# ST7789 Debug Console

`ST7789DebugConsole` is a small PicoRuby-oriented text console for the
Waveshare 1.3inch 240x240 LCD Module using the ST7789 controller.

It is designed for debug output while developing the MPU-6050 bicycle sensor. The implementation intentionally avoids a full 240x240 RGB565 framebuffer.

## Memory Model

A full RGB565 framebuffer would require:

```text
240 * 240 * 2 = 115,200 bytes
```

That is too large for the intended PicoRuby use. Instead, the console writes directly to the display using small pixel chunks:

- `fill_rect` writes repeated RGB565 pixels in configurable chunks.
- `draw_char` builds one 8x8 character cell, 128 bytes.
- text scrolling keeps only a ring of short line strings.
- a new line is drawn by itself until the display is full.

For a 240x240 display using 8x8 cells, the default console is:

- 30 columns
- 30 rows
- ASCII only

## Wiring

The module expects an SPI object and GPIO objects for control pins:

```ruby
spi = SPI.new(
  unit: :RP2040_SPI0,
  frequency: 24_000_000,
  sck_pin: 18,
  cipo_pin: -1,
  copi_pin: 19,
  cs_pin: 17,
  mode: 0
)

dc = GPIO.new(20, GPIO::OUT)
rst = GPIO.new(21, GPIO::OUT)
bl = GPIO.new(22, GPIO::OUT)

lcd = ST7789DebugConsole.new(spi, dc, rst, bl)
```

Use `:RP2040_SPI0` or `:RP2040_SPI1` depending on the pins you wire. On PicoRuby for RP2040/RP2350 targets, the unit names still use the `RP2040_SPI*` form.

If your LCD module does not expose MISO/CIPO, pass `cipo_pin: -1`.

## Display Options

The fifth constructor argument is an option hash:

```ruby
lcd = ST7789DebugConsole.new(
  spi,
  dc,
  rst,
  bl,
  :width => 240,
  :height => 240,
  :x_offset => 0,
  :y_offset => 0,
  :madctl => 0x70,
  :invert => true,
  :foreground => ST7789DebugConsole::GREEN,
  :background => ST7789DebugConsole::BLACK,
  :chunk_pixels => 64
)
```

Important options:

- `:x_offset`, `:y_offset`: panel-specific RAM offsets.
- `:madctl`: ST7789 memory access control value for rotation and RGB/BGR order.
- `:invert`: sends `INVON` when true and `INVOFF` when false.
- `:foreground`, `:background`: RGB565 text colors.
- `:chunk_pixels`: maximum pixels per generated fill chunk.
- `:auto_init`: set false in tests or when initialization is handled elsewhere.
- `:clear_on_init`: set false to avoid clearing the screen at startup.

The defaults match the Waveshare 1.3inch LCD Module:

- `:madctl => 0x70`
- `:x_offset => 0`
- `:y_offset => 0`
- `:invert => true`

The initialization sequence includes the porch, gate, VCOM, frame-rate,
power, and gamma settings from the Waveshare driver. The backlight remains
off until initialization and the startup clear are complete.

## PicoRuby Binary Strings

PicoRuby encodes `String.new << integer` as UTF-8 when the integer is 0x80 or
greater. RGB565 data must contain exact bytes, so the driver creates fixed-size
strings and writes each byte with `String#setbyte`.

Without this handling, black pixels still look correct, but colored text
expands into extra bytes and loses pixel alignment.

The same issue affects address windows. For example, coordinate 239 must be
sent as byte `0xef`; UTF-8 expansion changes the command length and can leave
only part of the panel cleared while the remaining area shows old RAM noise.

## Troubleshooting

For the Waveshare module, start with the values in
`examples/st7789_debug_console_verify.rb`.

- A partly black panel with noise elsewhere usually indicates corrupted
  `CASET` or `RASET` bytes. Use the current `setbyte`-based driver.
- Colored pixels or unreadable glyphs usually indicate corrupted RGB565
  bytes. Do not replace the binary builders with `String#<< integer`.
- A correct image with intermittent speckles can indicate wiring or SPI
  signal integrity. Verify ground and shorten jumper wires before reducing the
  default 24 MHz SPI frequency.
- If the image is rotated but otherwise correct, change `:madctl`; keep the
  Waveshare default `0x70` while first verifying communication.

## API

Common methods:

- `write_line(text)`: append one debug line. It redraws all rows only after
  scrolling starts.
- `puts(text)`: alias-like convenience method for `write_line`.
- `clear`: clear the LCD and reset the line ring.
- `backlight(on)`: control the backlight pin when one is provided.
- `color(fg, bg = nil)`: change text colors for subsequent draws.
- `fill_rect(x, y, w, h, color)`: fill a rectangle.
- `draw_char(x, y, ch, fg, bg)`: draw one 8x8 ASCII cell.
- `draw_text_line(row, text)`: draw one row.

Low-level ST7789 helpers:

- `command(byte)`
- `data(byte_or_string)`
- `set_window(x0, y0, x1, y1)`
- `write_pixels(rgb565_data)`

## Verification Example

Use:

```ruby
examples/st7789_debug_console_verify.rb
```

Update the pin constants at the top of the file, copy it with `lib/st7789_debug_console.rb` to R2P2, and run it. It clears the screen, prints basic display information, and appends a counter once per second.

## Integration With MPU-6050 Debugging

For sensor debugging, keep serial output for detailed logs and send only compact status lines to the LCD. Good candidates are:

- `EVENT count`
- selected axis
- `gyro_dps`
- `angle`
- `dt_skipped`

Avoid printing every high-rate sample to the LCD. The console draws text rows
directly over SPI, which is acceptable for debug status but not for high-rate
telemetry.

## Limitations

- ASCII fixed-width font only.
- No Japanese font.
- No image drawing.
- No full-screen framebuffer.
- Full redraw is still required after the 30-line ring starts scrolling.
- No hardware validation is performed by the host tests.

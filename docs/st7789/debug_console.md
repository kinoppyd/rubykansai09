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

- `fill_rect` keeps chip select active while streaming reusable RGB565 chunks.
- `draw_char` builds one 8x8 character cell, 128 bytes.
- the 5x7 font is one 480-byte String instead of an Array of 480 Integer
  objects.
- text output keeps only a ring of short line strings.
- `draw_text_line` rasterizes into a compact 1-bit mask: 240 bytes at scale 1
  or 480 bytes at scale 2.
- RGB565 pixels are streamed in groups of at most 64 bytes; no 3,840-byte
  line buffer is retained or allocated by the SPI layer.
- the default `:page` mode clears the previous page before returning to the
  first physical row.

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
  :scroll_mode => :page,
  :text_scale => 2,
  :foreground => ST7789DebugConsole::GREEN,
  :background => ST7789DebugConsole::BLACK,
  :chunk_pixels => 127
)
```

Important options:

- `:x_offset`, `:y_offset`: panel-specific RAM offsets.
- `:madctl`: ST7789 memory access control value for rotation and RGB/BGR order.
- `:invert`: sends `INVON` when true and `INVOFF` when false.
- `:foreground`, `:background`: RGB565 text colors.
- `:scroll_mode`: `:page` clears at the page boundary, `:wrap` overwrites one
  physical row, and `:redraw` performs conventional scrolling by redrawing all
  rows.
- `:text_scale`: integer glyph scale. Use `1` for 8x8 cells or `2` for 16x16
  cells.
- `:chunk_pixels`: pixels per fill transfer. Values are clamped to `1..127` so
  each RGB565 write remains below PicoRuby SPI's 256-byte heap threshold.
- `:auto_init`: set false in tests or when initialization is handled elsewhere.
- `:clear_on_init`: set false to avoid clearing the screen at startup.

The defaults match the Waveshare 1.3inch LCD Module:

- `:madctl => 0x70`
- `:x_offset => 0`
- `:y_offset => 0`
- `:invert => true`
- `:scroll_mode => :page`
- `:text_scale => 1`

The initialization sequence includes the porch, gate, VCOM, frame-rate,
power, and gamma settings from the Waveshare driver. The backlight remains
off until initialization and the startup clear are complete.

## Rendering and Overflow

At scale 1, each 8-pixel-high text row contains 3,840 RGB565 bytes. At scale 2,
each 16-pixel-high row contains 7,680 bytes. The driver prepares the complete
text as a compact 1-bit mask before setting the LCD address window. It then
expands two pixels at a time through four reusable RGB565 patterns. Each
`SPI#write` contains at most 64 bytes, below PicoRuby SPI's 256-byte
stack-buffer boundary, so the SPI layer does not request a heap buffer.

## Text Size

Set `:text_scale => 2` for larger debug text. The 5x7 glyph pixels and the
surrounding 8x8 cell are doubled in both directions.

| Scale | Cell | Columns | Rows | Mask memory |
| --- | --- | ---: | ---: | ---: |
| `1` | 8x8 | 30 | 30 | 240 bytes |
| `2` | 16x16 | 15 | 15 | 480 bytes |

Scale 2 is used by `examples/st7789_debug_console_verify.rb`. Scale 1 remains
the library default for compatibility and minimum memory use.

This replaces the previous 3,840-byte persistent line buffer. That buffer was
also copied into another 3,840-byte allocation by `SPI#write`, which could
raise `NoMemoryError` immediately on an R2P2 heap already holding the MPU-6050
and BLE objects.

The default `:scroll_mode => :page` is intended for embedded debug output.
After the last row, it erases only the tracked text rectangles and retained
line strings before drawing the next line at physical row 0. The unchanged
background is not transferred again, so page changes are faster than a full
115,200-byte clear.

Set `:scroll_mode => :wrap` only when the lowest possible overflow latency is
required. It overwrites physical rows in a circle without clearing the other
rows, so old content remains visible until each row is replaced.

Set `:scroll_mode => :redraw` when conventional terminal-like scrolling is
more important than latency. That mode redraws all visible rows after every
new line once the display is full. The optimized line renderer makes it faster
than the original implementation, but it must still rasterize and transfer a
complete 115,200-byte screen.

The ST7789 hardware vertical-scroll commands are not used with the Waveshare
default `MADCTL=0x70`. That setting has the `MV` bit enabled, while the ST7789
[datasheet](https://www.lcd-module.com/fileadmin/eng/pdf/zubehoer/ST7789V.pdf)
requires `MV=0` for vertical-scrolling frame-memory writes.

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

- `write_line(text)`: append one debug line using the selected scroll mode.
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
- `:page` clears the previous page before returning to row 0.
- `:wrap` uses circular physical rows and leaves other old rows visible.
- `:redraw` provides conventional scrolling but transfers a complete screen.
- No hardware validation is performed by the host tests.

# Usage:
#   require "spi"
#   require "gpio"
#   require "st7789_debug_console"
#   spi = SPI.new(unit: :RP2040_SPI0, frequency: 24_000_000,
#                 sck_pin: 18, cipo_pin: -1, copi_pin: 19, cs_pin: 17)
#   dc = GPIO.new(20, GPIO::OUT)
#   rst = GPIO.new(21, GPIO::OUT)
#   bl = GPIO.new(22, GPIO::OUT)
#   lcd = ST7789DebugConsole.new(
#     spi, dc, rst, bl,
#     :madctl => 0x70 # Waveshare 1.3inch LCD Module
#   )
#   lcd.write_line("MPU6050 debug")
#   lcd.write_line("axis y gyro 123")
#
# Text-only ST7789 debug console for the 240x240 Waveshare 1.3inch LCD Module.
# It avoids a full framebuffer and draws fixed-size ASCII cells directly.

class ST7789DebugConsole
  BLACK = 0x0000
  WHITE = 0xffff
  RED = 0xf800
  GREEN = 0x07e0
  BLUE = 0x001f
  YELLOW = 0xffe0
  CYAN = 0x07ff
  MAGENTA = 0xf81f

  SWRESET = 0x01
  SLPOUT = 0x11
  NORON = 0x13
  INVOFF = 0x20
  INVON = 0x21
  CASET = 0x2a
  RASET = 0x2b
  RAMWR = 0x2c
  MADCTL = 0x36
  COLMOD = 0x3a
  DISPON = 0x29
  PORCTRL = 0xb2
  GCTRL = 0xb7
  VCOMS = 0xbb
  LCMCTRL = 0xc0
  VDVVRHEN = 0xc2
  VRHS = 0xc3
  VDVS = 0xc4
  FRCTRL2 = 0xc6
  PWCTRL1 = 0xd0
  PVGAMCTRL = 0xe0
  NVGAMCTRL = 0xe1

  FONT = [
    0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x5f,0x00,0x00, 0x00,0x07,0x00,0x07,0x00, 0x14,0x7f,0x14,0x7f,0x14,
    0x24,0x2a,0x7f,0x2a,0x12, 0x23,0x13,0x08,0x64,0x62, 0x36,0x49,0x55,0x22,0x50, 0x00,0x05,0x03,0x00,0x00,
    0x00,0x1c,0x22,0x41,0x00, 0x00,0x41,0x22,0x1c,0x00, 0x14,0x08,0x3e,0x08,0x14, 0x08,0x08,0x3e,0x08,0x08,
    0x00,0x50,0x30,0x00,0x00, 0x08,0x08,0x08,0x08,0x08, 0x00,0x60,0x60,0x00,0x00, 0x20,0x10,0x08,0x04,0x02,
    0x3e,0x51,0x49,0x45,0x3e, 0x00,0x42,0x7f,0x40,0x00, 0x42,0x61,0x51,0x49,0x46, 0x21,0x41,0x45,0x4b,0x31,
    0x18,0x14,0x12,0x7f,0x10, 0x27,0x45,0x45,0x45,0x39, 0x3c,0x4a,0x49,0x49,0x30, 0x01,0x71,0x09,0x05,0x03,
    0x36,0x49,0x49,0x49,0x36, 0x06,0x49,0x49,0x29,0x1e, 0x00,0x36,0x36,0x00,0x00, 0x00,0x56,0x36,0x00,0x00,
    0x08,0x14,0x22,0x41,0x00, 0x14,0x14,0x14,0x14,0x14, 0x00,0x41,0x22,0x14,0x08, 0x02,0x01,0x51,0x09,0x06,
    0x32,0x49,0x79,0x41,0x3e, 0x7e,0x11,0x11,0x11,0x7e, 0x7f,0x49,0x49,0x49,0x36, 0x3e,0x41,0x41,0x41,0x22,
    0x7f,0x41,0x41,0x22,0x1c, 0x7f,0x49,0x49,0x49,0x41, 0x7f,0x09,0x09,0x09,0x01, 0x3e,0x41,0x49,0x49,0x7a,
    0x7f,0x08,0x08,0x08,0x7f, 0x00,0x41,0x7f,0x41,0x00, 0x20,0x40,0x41,0x3f,0x01, 0x7f,0x08,0x14,0x22,0x41,
    0x7f,0x40,0x40,0x40,0x40, 0x7f,0x02,0x0c,0x02,0x7f, 0x7f,0x04,0x08,0x10,0x7f, 0x3e,0x41,0x41,0x41,0x3e,
    0x7f,0x09,0x09,0x09,0x06, 0x3e,0x41,0x51,0x21,0x5e, 0x7f,0x09,0x19,0x29,0x46, 0x46,0x49,0x49,0x49,0x31,
    0x01,0x01,0x7f,0x01,0x01, 0x3f,0x40,0x40,0x40,0x3f, 0x1f,0x20,0x40,0x20,0x1f, 0x3f,0x40,0x38,0x40,0x3f,
    0x63,0x14,0x08,0x14,0x63, 0x07,0x08,0x70,0x08,0x07, 0x61,0x51,0x49,0x45,0x43, 0x00,0x7f,0x41,0x41,0x00,
    0x02,0x04,0x08,0x10,0x20, 0x00,0x41,0x41,0x7f,0x00, 0x04,0x02,0x01,0x02,0x04, 0x40,0x40,0x40,0x40,0x40,
    0x00,0x01,0x02,0x04,0x00, 0x20,0x54,0x54,0x54,0x78, 0x7f,0x48,0x44,0x44,0x38, 0x38,0x44,0x44,0x44,0x20,
    0x38,0x44,0x44,0x48,0x7f, 0x38,0x54,0x54,0x54,0x18, 0x08,0x7e,0x09,0x01,0x02, 0x0c,0x52,0x52,0x52,0x3e,
    0x7f,0x08,0x04,0x04,0x78, 0x00,0x44,0x7d,0x40,0x00, 0x20,0x40,0x44,0x3d,0x00, 0x7f,0x10,0x28,0x44,0x00,
    0x00,0x41,0x7f,0x40,0x00, 0x7c,0x04,0x18,0x04,0x78, 0x7c,0x08,0x04,0x04,0x78, 0x38,0x44,0x44,0x44,0x38,
    0x7c,0x14,0x14,0x14,0x08, 0x08,0x14,0x14,0x18,0x7c, 0x7c,0x08,0x04,0x04,0x08, 0x48,0x54,0x54,0x54,0x20,
    0x04,0x3f,0x44,0x40,0x20, 0x3c,0x40,0x40,0x20,0x7c, 0x1c,0x20,0x40,0x20,0x1c, 0x3c,0x40,0x30,0x40,0x3c,
    0x44,0x28,0x10,0x28,0x44, 0x0c,0x50,0x50,0x50,0x3c, 0x44,0x64,0x54,0x4c,0x44, 0x00,0x08,0x36,0x41,0x00,
    0x00,0x00,0x7f,0x00,0x00, 0x00,0x41,0x36,0x08,0x00, 0x08,0x04,0x08,0x10,0x08, 0x00,0x06,0x09,0x09,0x06
  ]

  attr_reader :width, :height, :cols, :rows

  def initialize(spi, dc, rst = nil, bl = nil, o = nil)
    @spi = spi
    @dc = dc
    @rst = rst
    @bl = bl
    @width = opt(o, :width, 240)
    @height = opt(o, :height, 240)
    @xoff = opt(o, :x_offset, 0)
    @yoff = opt(o, :y_offset, 0)
    @cw = opt(o, :char_width, 8)
    @ch = opt(o, :char_height, 8)
    @cols = opt(o, :cols, @width / @cw)
    @rows = opt(o, :rows, @height / @ch)
    @fg = opt(o, :foreground, GREEN)
    @bg = opt(o, :background, BLACK)
    @madctl = opt(o, :madctl, 0x70)
    @invert = opt(o, :invert, true)
    @chunk_pixels = opt(o, :chunk_pixels, 64)
    @lines = []
    i = 0
    while i < @rows
      @lines << ""
      i += 1
    end
    @head = 0
    @line_count = 0
    backlight_on = opt(o, :backlight, true)
    backlight(false) if @bl
    init_display if opt(o, :auto_init, true)
    clear if opt(o, :clear_on_init, true)
    backlight(backlight_on) if @bl
  end

  def init_display
    reset
    command(SWRESET)
    delay_ms(150)
    command_data(MADCTL, byte_string(@madctl))
    command_data(COLMOD, "\x05")
    command_data(PORCTRL, "\x0c\x0c\x00\x33\x33")
    command_data(GCTRL, "\x35")
    command_data(VCOMS, "\x19")
    command_data(LCMCTRL, "\x2c")
    command_data(VDVVRHEN, "\x01")
    command_data(VRHS, "\x12")
    command_data(VDVS, "\x20")
    command_data(FRCTRL2, "\x0f")
    command_data(PWCTRL1, "\xa4\xa1")
    command_data(
      PVGAMCTRL,
      "\xd0\x04\x0d\x11\x13\x2b\x3f\x54\x4c\x18\x0d\x0b\x1f\x23"
    )
    command_data(
      NVGAMCTRL,
      "\xd0\x04\x0c\x11\x13\x2c\x3f\x44\x51\x2f\x1f\x1f\x20\x23"
    )
    command(@invert ? INVON : INVOFF)
    command(SLPOUT)
    delay_ms(120)
    command(NORON)
    delay_ms(10)
    command(DISPON)
    delay_ms(20)
    self
  end

  def reset
    return self if @rst.nil?
    @rst.write(1)
    delay_ms(10)
    @rst.write(0)
    delay_ms(10)
    @rst.write(1)
    delay_ms(120)
    self
  end

  def command(c)
    @dc.write(0)
    spi_write(c)
    self
  end

  def command_data(c, payload)
    if @spi.respond_to?(:select)
      @spi.select do |s|
        @dc.write(0)
        s.write(c)
        @dc.write(1)
        s.write(payload)
      end
    else
      @dc.write(0)
      @spi.write(c)
      @dc.write(1)
      @spi.write(payload)
    end
    self
  end

  def data(v)
    @dc.write(1)
    spi_write(v)
    self
  end

  def set_window(x0, y0, x1, y1)
    x0 += @xoff
    x1 += @xoff
    y0 += @yoff
    y1 += @yoff
    command_data(CASET, u16_pair(x0, x1))
    command_data(RASET, u16_pair(y0, y1))
    command(RAMWR)
    self
  end

  def write_pixels(rgb565_data)
    data(rgb565_data)
  end

  def fill_rect(x, y, w, h, color = nil)
    color = @bg if color.nil?
    return self if w <= 0 || h <= 0
    return self if x >= @width || y >= @height
    if x < 0
      w += x
      x = 0
    end
    if y < 0
      h += y
      y = 0
    end
    w = @width - x if x + w > @width
    h = @height - y if y + h > @height
    return self if w <= 0 || h <= 0
    set_window(x, y, x + w - 1, y + h - 1)
    pixels = w * h
    while pixels > 0
      n = pixels < @chunk_pixels ? pixels : @chunk_pixels
      data(pixel_run(n, color))
      pixels -= n
    end
    self
  end

  def clear
    i = 0
    while i < @rows
      @lines[i] = ""
      i += 1
    end
    @head = 0
    @line_count = 0
    fill_rect(0, 0, @width, @height, @bg)
  end

  def backlight(on = true)
    @bl.write(on ? 1 : 0) if @bl
    self
  end

  def color(fg, bg = nil)
    @fg = fg
    @bg = bg unless bg.nil?
    self
  end

  def write_line(text)
    text = normalize_text(text)
    row = @line_count
    @lines[@head] = text
    @head += 1
    @head = 0 if @head >= @rows
    if @line_count < @rows
      @line_count += 1
      draw_text_line(row, text)
    else
      redraw
    end
    self
  end

  def puts(text = "")
    write_line(text)
  end

  def redraw
    row = 0
    while row < @rows
      draw_text_line(row, line_at(row))
      row += 1
    end
    self
  end

  def draw_text_line(row, text)
    y = row * @ch
    line_width = @cols * @cw
    line_width = @width if line_width > @width
    set_window(0, y, line_width - 1, y + @ch - 1)
    pixel_row = 0
    while pixel_row < @ch
      data(text_pixel_row(text, pixel_row, line_width))
      pixel_row += 1
    end
    self
  end

  def draw_char(x, y, ch, fg = nil, bg = nil)
    fg = @fg if fg.nil?
    bg = @bg if bg.nil?
    set_window(x, y, x + @cw - 1, y + @ch - 1)
    data(char_pixels(ch, fg, bg))
    self
  end

  def line_at(row)
    return "" if row < 0 || row >= @rows
    return @lines[row] if @line_count < @rows
    @lines[(@head + row) % @rows]
  end

  def opt(o, k, d)
    return d if o.nil?
    v = o[k]
    v.nil? ? d : v
  end

  def spi_write(v)
    if @spi.respond_to?(:select)
      @spi.select do |s|
        s.write(v)
      end
    else
      @spi.write(v)
    end
  end

  def u16_pair(a, b)
    s = "\0" * 4
    s.setbyte(0, (a >> 8) & 255)
    s.setbyte(1, a & 255)
    s.setbyte(2, (b >> 8) & 255)
    s.setbyte(3, b & 255)
    s
  end

  def pixel_run(n, color)
    s = "\0" * (n * 2)
    hi = (color >> 8) & 255
    lo = color & 255
    i = 0
    pos = 0
    while i < n
      s.setbyte(pos, hi)
      s.setbyte(pos + 1, lo)
      pos += 2
      i += 1
    end
    s
  end

  def char_pixels(ch, fg, bg)
    s = "\0" * (@cw * @ch * 2)
    row = 0
    pos = 0
    while row < @ch
      col = 0
      while col < @cw
        bits = col < 5 && row < 7 ? font_byte(ch, col) : 0
        color = ((bits >> row) & 1) == 1 ? fg : bg
        s.setbyte(pos, (color >> 8) & 255)
        s.setbyte(pos + 1, color & 255)
        pos += 2
        col += 1
      end
      row += 1
    end
    s
  end

  def text_pixel_row(text, glyph_row, line_width)
    s = "\0" * (line_width * 2)
    cell = 0
    pos = 0
    while cell < @cols && pos < s.bytesize
      ch = cell < text.bytesize ? text.getbyte(cell) : 32
      pixel_col = 0
      while pixel_col < @cw && pos < s.bytesize
        bits = pixel_col < 5 && glyph_row < 7 ? font_byte(ch, pixel_col) : 0
        color = ((bits >> glyph_row) & 1) == 1 ? @fg : @bg
        s.setbyte(pos, (color >> 8) & 255)
        s.setbyte(pos + 1, color & 255)
        pos += 2
        pixel_col += 1
      end
      cell += 1
    end
    s
  end

  def byte_string(value)
    s = "\0" * 1
    s.setbyte(0, value & 255)
    s
  end

  def font_byte(ch, col)
    ch = 63 if ch < 32 || ch > 127
    FONT[(ch - 32) * 5 + col]
  end

  def normalize_text(text)
    src = text.to_s
    out = String.new
    i = 0
    while i < src.bytesize && out.bytesize < @cols
      c = src.getbyte(i)
      break if c == 10 || c == 13
      out << (c >= 32 && c <= 126 ? c : 63)
      i += 1
    end
    out
  end

  def delay_ms(ms)
    if Object.const_defined?(:Machine) && Machine.respond_to?(:delay_ms)
      Machine.delay_ms(ms)
    end
    nil
  end
end

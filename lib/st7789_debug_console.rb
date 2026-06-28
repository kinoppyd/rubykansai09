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
#     :madctl => 0x70, # Waveshare 1.3inch LCD Module
#     :scroll_mode => :page,
#     :text_scale => 2
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

  FONT =
    "\x00\x00\x00\x00\x00\x00\x00\x5f\x00\x00\x00\x07\x00\x07\x00\x14\x7f\x14\x7f\x14" \
    "\x24\x2a\x7f\x2a\x12\x23\x13\x08\x64\x62\x36\x49\x55\x22\x50\x00\x05\x03\x00\x00" \
    "\x00\x1c\x22\x41\x00\x00\x41\x22\x1c\x00\x14\x08\x3e\x08\x14\x08\x08\x3e\x08\x08" \
    "\x00\x50\x30\x00\x00\x08\x08\x08\x08\x08\x00\x60\x60\x00\x00\x20\x10\x08\x04\x02" \
    "\x3e\x51\x49\x45\x3e\x00\x42\x7f\x40\x00\x42\x61\x51\x49\x46\x21\x41\x45\x4b\x31" \
    "\x18\x14\x12\x7f\x10\x27\x45\x45\x45\x39\x3c\x4a\x49\x49\x30\x01\x71\x09\x05\x03" \
    "\x36\x49\x49\x49\x36\x06\x49\x49\x29\x1e\x00\x36\x36\x00\x00\x00\x56\x36\x00\x00" \
    "\x08\x14\x22\x41\x00\x14\x14\x14\x14\x14\x00\x41\x22\x14\x08\x02\x01\x51\x09\x06" \
    "\x32\x49\x79\x41\x3e\x7e\x11\x11\x11\x7e\x7f\x49\x49\x49\x36\x3e\x41\x41\x41\x22" \
    "\x7f\x41\x41\x22\x1c\x7f\x49\x49\x49\x41\x7f\x09\x09\x09\x01\x3e\x41\x49\x49\x7a" \
    "\x7f\x08\x08\x08\x7f\x00\x41\x7f\x41\x00\x20\x40\x41\x3f\x01\x7f\x08\x14\x22\x41" \
    "\x7f\x40\x40\x40\x40\x7f\x02\x0c\x02\x7f\x7f\x04\x08\x10\x7f\x3e\x41\x41\x41\x3e" \
    "\x7f\x09\x09\x09\x06\x3e\x41\x51\x21\x5e\x7f\x09\x19\x29\x46\x46\x49\x49\x49\x31" \
    "\x01\x01\x7f\x01\x01\x3f\x40\x40\x40\x3f\x1f\x20\x40\x20\x1f\x3f\x40\x38\x40\x3f" \
    "\x63\x14\x08\x14\x63\x07\x08\x70\x08\x07\x61\x51\x49\x45\x43\x00\x7f\x41\x41\x00" \
    "\x02\x04\x08\x10\x20\x00\x41\x41\x7f\x00\x04\x02\x01\x02\x04\x40\x40\x40\x40\x40" \
    "\x00\x01\x02\x04\x00\x20\x54\x54\x54\x78\x7f\x48\x44\x44\x38\x38\x44\x44\x44\x20" \
    "\x38\x44\x44\x48\x7f\x38\x54\x54\x54\x18\x08\x7e\x09\x01\x02\x0c\x52\x52\x52\x3e" \
    "\x7f\x08\x04\x04\x78\x00\x44\x7d\x40\x00\x20\x40\x44\x3d\x00\x7f\x10\x28\x44\x00" \
    "\x00\x41\x7f\x40\x00\x7c\x04\x18\x04\x78\x7c\x08\x04\x04\x78\x38\x44\x44\x44\x38" \
    "\x7c\x14\x14\x14\x08\x08\x14\x14\x18\x7c\x7c\x08\x04\x04\x08\x48\x54\x54\x54\x20" \
    "\x04\x3f\x44\x40\x20\x3c\x40\x40\x20\x7c\x1c\x20\x40\x20\x1c\x3c\x40\x30\x40\x3c" \
    "\x44\x28\x10\x28\x44\x0c\x50\x50\x50\x3c\x44\x64\x54\x4c\x44\x00\x08\x36\x41\x00" \
    "\x00\x00\x7f\x00\x00\x00\x41\x36\x08\x00\x08\x04\x08\x10\x08\x00\x06\x09\x09\x06"

  attr_reader :width, :height, :cols, :rows, :text_scale

  def initialize(spi, dc, rst = nil, bl = nil, o = nil)
    @spi = spi
    @dc = dc
    @rst = rst
    @bl = bl
    @width = opt(o, :width, 240)
    @height = opt(o, :height, 240)
    @xoff = opt(o, :x_offset, 0)
    @yoff = opt(o, :y_offset, 0)
    @text_scale = opt(o, :text_scale, 1)
    @text_scale = 1 if @text_scale < 1
    @cw = opt(o, :char_width, 8 * @text_scale)
    @ch = opt(o, :char_height, 8 * @text_scale)
    @cols = opt(o, :cols, @width / @cw)
    @rows = opt(o, :rows, @height / @ch)
    @fg = opt(o, :foreground, GREEN)
    @bg = opt(o, :background, BLACK)
    @madctl = opt(o, :madctl, 0x70)
    @invert = opt(o, :invert, true)
    @chunk_pixels = opt(o, :chunk_pixels, 127)
    @chunk_pixels = 1 if @chunk_pixels < 1
    @chunk_pixels = 127 if @chunk_pixels > 127
    @scroll_mode = opt(o, :scroll_mode, :page)
    @line_width = @cols * @cw
    @line_width = @width if @line_width > @width
    @mask_stride = (@line_width + 7) / 8
    @text_masks = "\0" * (@mask_stride * @ch)
    @tail_pixels = @line_width & 7
    @tail_buffer = "\0" * (@tail_pixels * 2)
    build_pixel_pairs
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
    n = pixels < @chunk_pixels ? pixels : @chunk_pixels
    chunk = pixel_run(n, color)
    count = pixels / n
    rest = pixels - count * n
    tail = rest > 0 ? pixel_run(rest, color) : nil
    write_fill_chunks(chunk, count, tail)
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
    build_pixel_pairs
    self
  end

  def write_line(text)
    text = normalize_text(text)
    clear_text_page if @line_count >= @rows && @scroll_mode == :page
    row = @line_count < @rows ? @line_count : @head
    @lines[@head] = text
    @head += 1
    @head = 0 if @head >= @rows
    if @line_count < @rows
      @line_count += 1
      draw_text_line(row, text)
    elsif @scroll_mode == :redraw
      redraw
    else
      draw_text_line(row, text)
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
    render_text_masks(text)
    set_window(0, y, @line_width - 1, y + @ch - 1)
    write_text_pixels
    self
  end

  def draw_char(x, y, ch, fg = nil, bg = nil)
    fg = @fg if fg.nil?
    bg = @bg if bg.nil?
    set_window(x, y, x + @cw - 1, y + @ch - 1)
    row = 0
    while row < @ch
      data(char_pixel_row(ch, row, fg, bg))
      row += 1
    end
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

  def write_fill_chunks(chunk, count, tail)
    @dc.write(1)
    if @spi.respond_to?(:select)
      @spi.select do |s|
        write_fill_data(s, chunk, count, tail)
      end
    else
      write_fill_data(@spi, chunk, count, tail)
    end
    self
  end

  def write_fill_data(spi, chunk, count, tail)
    i = 0
    while i < count
      spi.write(chunk)
      i += 1
    end
    spi.write(tail) unless tail.nil?
    self
  end

  def clear_text_page
    row = 0
    while row < @line_count
      text = @lines[row]
      unless text.empty?
        width = (text.bytesize - 1) * @cw + 5 * @text_scale
        width = @line_width if width > @line_width
        height = 7 * @text_scale
        height = @ch if height > @ch
        fill_rect(0, row * @ch, width, height, @bg)
      end
      @lines[row] = ""
      row += 1
    end
    @head = 0
    @line_count = 0
    self
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

  def char_pixel_row(ch, row, fg, bg)
    s = "\0" * (@cw * 2)
    source_row = row / @text_scale
    fg_hi = (fg >> 8) & 255
    fg_lo = fg & 255
    bg_hi = (bg >> 8) & 255
    bg_lo = bg & 255
    col = 0
    pos = 0
    while col < @cw
      source_col = col / @text_scale
      on = false
      if source_col < 5 && source_row < 7
        bits = font_byte(ch, source_col)
        on = ((bits >> source_row) & 1) == 1
      end
      s.setbyte(pos, on ? fg_hi : bg_hi)
      s.setbyte(pos + 1, on ? fg_lo : bg_lo)
      pos += 2
      col += 1
    end
    s
  end

  def build_pixel_pairs
    @pixel_pairs = [] if @pixel_pairs.nil?
    mask = 0
    while mask < 4
      s = @pixel_pairs[mask]
      if s.nil?
        s = "\0" * 4
        @pixel_pairs << s
      end
      pixel = 0
      while pixel < 2
        color = (mask & (1 << (1 - pixel))) == 0 ? @bg : @fg
        pos = pixel * 2
        s.setbyte(pos, (color >> 8) & 255)
        s.setbyte(pos + 1, color & 255)
        pixel += 1
      end
      mask += 1
    end
    self
  end

  def render_text_masks(text)
    pos = 0
    while pos < @text_masks.bytesize
      @text_masks.setbyte(pos, 0)
      pos += 1
    end

    cell = 0
    while cell < @cols
      ch = text.getbyte(cell)
      break if ch.nil?
      pixel_col = 0
      while pixel_col < @cw
        source_col = pixel_col / @text_scale
        break if source_col >= 5
        x = cell * @cw + pixel_col
        break if x >= @line_width
        bits = font_byte(ch, source_col)
        pixel_row = 0
        while pixel_row < @ch
          source_row = pixel_row / @text_scale
          break if source_row >= 7
          if ((bits >> source_row) & 1) == 1
            pos = pixel_row * @mask_stride + (x >> 3)
            bit = 1 << (7 - (x & 7))
            @text_masks.setbyte(pos, @text_masks.getbyte(pos) | bit)
          end
          pixel_row += 1
        end
        pixel_col += 1
      end
      cell += 1
    end
    self
  end

  def write_text_pixels
    @dc.write(1)
    if @spi.respond_to?(:select)
      @spi.select do |s|
        write_mask_rows(s)
      end
    else
      write_mask_rows(@spi)
    end
    self
  end

  def write_mask_rows(spi)
    row = 0
    full_bytes = @line_width >> 3
    while row < @ch
      pos = row * @mask_stride
      remaining = full_bytes
      while remaining >= 4
        write_mask4(spi, pos)
        pos += 4
        remaining -= 4
      end
      if remaining >= 2
        write_mask2(spi, pos)
        pos += 2
        remaining -= 2
      end
      write_mask1(spi, pos) if remaining == 1
      write_tail_pixels(spi, row) if @tail_pixels > 0
      row += 1
    end
    self
  end

  def write_mask4(spi, pos)
    p = @pixel_pairs
    a = @text_masks
    b0 = a.getbyte(pos)
    b1 = a.getbyte(pos + 1)
    b2 = a.getbyte(pos + 2)
    b3 = a.getbyte(pos + 3)
    spi.write(
      p[(b0 >> 6) & 3], p[(b0 >> 4) & 3], p[(b0 >> 2) & 3], p[b0 & 3],
      p[(b1 >> 6) & 3], p[(b1 >> 4) & 3], p[(b1 >> 2) & 3], p[b1 & 3],
      p[(b2 >> 6) & 3], p[(b2 >> 4) & 3], p[(b2 >> 2) & 3], p[b2 & 3],
      p[(b3 >> 6) & 3], p[(b3 >> 4) & 3], p[(b3 >> 2) & 3], p[b3 & 3]
    )
  end

  def write_mask2(spi, pos)
    p = @pixel_pairs
    a = @text_masks
    b0 = a.getbyte(pos)
    b1 = a.getbyte(pos + 1)
    spi.write(
      p[(b0 >> 6) & 3], p[(b0 >> 4) & 3], p[(b0 >> 2) & 3], p[b0 & 3],
      p[(b1 >> 6) & 3], p[(b1 >> 4) & 3], p[(b1 >> 2) & 3], p[b1 & 3]
    )
  end

  def write_mask1(spi, pos)
    p = @pixel_pairs
    b = @text_masks.getbyte(pos)
    spi.write(
      p[(b >> 6) & 3], p[(b >> 4) & 3], p[(b >> 2) & 3], p[b & 3]
    )
  end

  def write_tail_pixels(spi, row)
    mask = @text_masks.getbyte(row * @mask_stride + @mask_stride - 1)
    pixel = 0
    pos = 0
    while pixel < @tail_pixels
      color = (mask & (1 << (7 - pixel))) == 0 ? @bg : @fg
      @tail_buffer.setbyte(pos, (color >> 8) & 255)
      @tail_buffer.setbyte(pos + 1, color & 255)
      pixel += 1
      pos += 2
    end
    spi.write(@tail_buffer)
  end

  def byte_string(value)
    s = "\0" * 1
    s.setbyte(0, value & 255)
    s
  end

  def font_byte(ch, col)
    ch = 63 if ch < 32 || ch > 127
    FONT.getbyte((ch - 32) * 5 + col)
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

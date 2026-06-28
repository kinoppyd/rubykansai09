# Usage:
#   ruby -Ilib test/st7789_debug_console_test.rb
#
# Host-side tests for the ST7789 debug console using fake SPI/GPIO objects.

require "minitest/autorun"
require "st7789_debug_console"

class ST7789DebugConsoleTest < Minitest::Test
  def test_font_uses_one_compact_string
    assert_instance_of String, ST7789DebugConsole::FONT
    assert_equal 480, ST7789DebugConsole::FONT.bytesize
  end

  def test_initialization_sequence
    spi = FakeSPI.new
    dc = FakePin.new
    rst = FakePin.new
    bl = FakePin.new

    ST7789DebugConsole.new(spi, dc, rst, bl, :clear_on_init => false)

    bytes = spi.payload_bytes
    assert_includes bytes, ST7789DebugConsole::SWRESET
    assert_includes bytes, ST7789DebugConsole::SLPOUT
    assert_includes bytes, ST7789DebugConsole::COLMOD
    assert_includes bytes, 0x05
    assert_includes bytes, ST7789DebugConsole::MADCTL
    assert_includes bytes, 0x70
    assert_includes bytes, ST7789DebugConsole::PORCTRL
    assert_includes bytes, ST7789DebugConsole::PVGAMCTRL
    assert_includes bytes, ST7789DebugConsole::NVGAMCTRL
    assert_includes bytes, ST7789DebugConsole::INVON
    assert_includes bytes, ST7789DebugConsole::NORON
    assert_includes bytes, ST7789DebugConsole::DISPON
    assert_equal [1, 0, 1], rst.writes
    assert_equal [0, 1], bl.writes
  end

  def test_set_window_writes_address_commands
    spi = FakeSPI.new
    console = build_console(spi, :x_offset => 1, :y_offset => 2)

    console.set_window(1, 2, 3, 4)

    assert_equal [
      ST7789DebugConsole::CASET, 0, 2, 0, 4,
      ST7789DebugConsole::RASET, 0, 4, 0, 6,
      ST7789DebugConsole::RAMWR
    ], spi.payload_bytes
  end

  def test_full_panel_window_uses_exact_binary_coordinates
    spi = FakeSPI.new
    console = build_console(spi)

    console.set_window(0, 0, 239, 239)

    assert_equal [0, 0, 0, 239], bytes_of(spi.payloads[1])
    assert_equal [0, 0, 0, 239], bytes_of(spi.payloads[3])
    assert_equal 4, spi.payloads[1].bytesize
    assert_equal 4, spi.payloads[3].bytesize
  end

  def test_fill_rect_writes_rgb565_pixels_in_chunks
    spi = FakeSPI.new
    console = build_console(spi, :chunk_pixels => 2)

    console.fill_rect(0, 0, 2, 2, ST7789DebugConsole::RED)

    payloads = spi.payloads
    assert_equal [0xf8, 0x00, 0xf8, 0x00], bytes_of(payloads[-2])
    assert_equal [0xf8, 0x00, 0xf8, 0x00], bytes_of(payloads[-1])
  end

  def test_draw_char_writes_one_cell
    spi = FakeSPI.new
    console = build_console(spi)

    console.draw_char(0, 0, "A".ord, ST7789DebugConsole::WHITE, ST7789DebugConsole::BLACK)

    pixels = spi.payloads[-8, 8].join
    assert_equal 128, pixels.bytesize
    assert_includes bytes_of(pixels), 0xff
  end

  def test_rgb565_bytes_are_not_utf8_encoded
    spi = FakeSPI.new
    console = build_console(spi, :chunk_pixels => 1)

    console.fill_rect(0, 0, 1, 1, ST7789DebugConsole::MAGENTA)

    assert_equal [0xf8, 0x1f], bytes_of(spi.payloads[-1])
    assert_equal 2, spi.payloads[-1].bytesize
  end

  def test_write_line_uses_bounded_pixel_transfers
    spi = FakeSPI.new
    console = build_console(spi, :rows => 2, :cols => 4)

    console.write_line("one")

    assert_equal 13, spi.payloads.length
    assert_equal 8, spi.payloads[-8, 8].length
    assert spi.payloads[-8, 8].all? { |payload| payload.bytesize == 64 }
  end

  def test_default_line_avoids_large_rgb565_buffer
    spi = FakeSPI.new
    console = build_console(spi)

    console.write_line("MPU6050 debug")

    pixel_payloads = spi.payloads[5, spi.payloads.length - 5]
    assert_equal 3_840, pixel_payloads.inject(0) { |sum, value| sum + value.bytesize }
    assert_operator pixel_payloads.map(&:bytesize).max, :<=, 64
    assert_equal 240, console.instance_variable_get(:@text_masks).bytesize
    refute console.instance_variable_defined?(:@line_buffer)
  end

  def test_line_renderer_matches_character_renderer
    char_spi = FakeSPI.new
    char_console = build_console(char_spi, :rows => 1, :cols => 1)
    char_console.draw_char(0, 0, "A".ord)

    line_spi = FakeSPI.new
    line_console = build_console(line_spi, :rows => 1, :cols => 1)
    line_console.write_line("A")

    line_pixels = line_spi.payloads[-8, 8].join
    char_pixels = char_spi.payloads[-8, 8].join
    assert_equal bytes_of(char_pixels), bytes_of(line_pixels)
  end

  def test_text_scale_two_doubles_cells_and_glyph_pixels
    spi = FakeSPI.new
    console = build_console(
      spi,
      :width => 32,
      :height => 32,
      :text_scale => 2
    )

    assert_equal 2, console.text_scale
    assert_equal 2, console.cols
    assert_equal 2, console.rows

    console.write_line("A")
    pixels = spi.payloads[-16, 16].join

    assert_equal 32 * 16 * 2, pixels.bytesize
    assert_equal ST7789DebugConsole::BLACK, rgb565_at(pixels, 32, 0, 0)
    assert_equal ST7789DebugConsole::GREEN, rgb565_at(pixels, 32, 0, 2)
    assert_equal ST7789DebugConsole::GREEN, rgb565_at(pixels, 32, 1, 3)
    assert_equal ST7789DebugConsole::BLACK, rgb565_at(pixels, 32, 10, 3)
    assert_equal 64, console.instance_variable_get(:@text_masks).bytesize
  end

  def test_write_line_truncates_and_wraps_without_redraw
    spi = FakeSPI.new
    console = build_console(
      spi,
      :rows => 2,
      :cols => 4,
      :scroll_mode => :wrap
    )

    console.write_line("abcdef")
    assert_equal "abcd", console.line_at(0)
    assert_equal "", console.line_at(1)
    assert_equal 13, spi.payloads.length

    console.write_line("two")
    assert_equal 26, spi.payloads.length
    console.write_line("three")
    assert_equal "two", console.line_at(0)
    assert_equal "thre", console.line_at(1)
    assert_equal 39, spi.payloads.length
    assert_equal [0, 0, 0, 31], bytes_of(spi.payloads[-12])
    assert_equal [0, 0, 0, 7], bytes_of(spi.payloads[-10])
  end

  def test_default_page_mode_clears_before_returning_to_first_row
    spi = FakeSPI.new
    console = build_console(
      spi,
      :width => 32,
      :height => 16,
      :rows => 2,
      :cols => 4,
      :chunk_pixels => 64
    )

    console.write_line("one")
    console.write_line("two")
    console.write_line("three")

    assert_equal "thre", console.line_at(0)
    assert_equal "", console.line_at(1)
    assert_equal 1, console.instance_variable_get(:@line_count)

    third_write = spi.payloads[-29, 29]
    assert_equal [0, 0, 0, 20], bytes_of(third_write[1])
    assert_equal [0, 0, 0, 6], bytes_of(third_write[3])
    assert_equal [0] * 128, bytes_of(third_write[5])
    assert_equal [0, 8, 0, 14], bytes_of(third_write[11])
    assert_equal [0, 0, 0, 31], bytes_of(third_write[17])
    assert_equal [0, 0, 0, 7], bytes_of(third_write[19])
  end

  def test_redraw_scroll_mode_keeps_logical_order
    spi = FakeSPI.new
    console = build_console(
      spi,
      :rows => 2,
      :cols => 4,
      :scroll_mode => :redraw
    )

    console.write_line("one")
    console.write_line("two")
    console.write_line("three")

    assert_equal "two", console.line_at(0)
    assert_equal "thre", console.line_at(1)
    assert_equal 52, spi.payloads.length
  end

  def test_text_mask_clears_old_glyphs
    spi = FakeSPI.new
    console = build_console(spi, :rows => 2, :cols => 1)

    console.write_line("A")
    first = bytes_of(spi.payloads[-8, 8].join)
    console.write_line("")
    second = bytes_of(spi.payloads[-8, 8].join)

    assert_includes first, 0x07
    assert_equal [0] * (8 * 8 * 2), second
  end

  def build_console(spi, opts = nil)
    ST7789DebugConsole.new(spi, FakePin.new, nil, nil, merge_opts(opts))
  end

  def merge_opts(opts)
    base = {
      :auto_init => false,
      :clear_on_init => false,
      :width => 240,
      :height => 240
    }
    return base if opts.nil?
    opts.each do |k, v|
      base[k] = v
    end
    base
  end

  def bytes_of(v)
    return [v] if v.is_a?(Integer)
    a = []
    i = 0
    while i < v.bytesize
      a << v.getbyte(i)
      i += 1
    end
    a
  end

  def rgb565_at(data, width, x, y)
    pos = (y * width + x) * 2
    (data.getbyte(pos) << 8) | data.getbyte(pos + 1)
  end

  class FakeSPI
    attr_reader :payloads

    def initialize
      @payloads = []
    end

    def select
      yield self
    end

    def write(*values)
      value = values.length == 1 ? values[0] : values.join
      @payloads << (value.is_a?(String) ? value.dup : value)
      true
    end

    def payload_bytes
      out = []
      @payloads.each do |payload|
        if payload.is_a?(Integer)
          out << payload
        else
          i = 0
          while i < payload.bytesize
            out << payload.getbyte(i)
            i += 1
          end
        end
      end
      out
    end
  end

  class FakePin
    attr_reader :writes

    def initialize
      @writes = []
    end

    def write(v)
      @writes << v
      true
    end
  end
end

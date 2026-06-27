# Usage:
#   ruby -Ilib test/st7789_debug_console_test.rb
#
# Host-side tests for the ST7789 debug console using fake SPI/GPIO objects.

require "minitest/autorun"
require "st7789_debug_console"

class ST7789DebugConsoleTest < Minitest::Test
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

    pixels = spi.payloads[-1]
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

  def test_write_line_uses_one_pixel_transfer
    spi = FakeSPI.new
    console = build_console(spi, :rows => 2, :cols => 4)

    console.write_line("one")

    assert_equal 6, spi.payloads.length
    assert_equal 4 * 8 * 8 * 2, spi.payloads[-1].bytesize
  end

  def test_line_renderer_matches_character_renderer
    char_spi = FakeSPI.new
    char_console = build_console(char_spi, :rows => 1, :cols => 1)
    char_console.draw_char(0, 0, "A".ord)

    line_spi = FakeSPI.new
    line_console = build_console(line_spi, :rows => 1, :cols => 1)
    line_console.write_line("A")

    assert_equal bytes_of(char_spi.payloads[-1]), bytes_of(line_spi.payloads[-1])
  end

  def test_write_line_truncates_and_wraps_without_redraw
    spi = FakeSPI.new
    console = build_console(spi, :rows => 2, :cols => 4)

    console.write_line("abcdef")
    assert_equal "abcd", console.line_at(0)
    assert_equal "", console.line_at(1)
    assert_equal 6, spi.payloads.length

    console.write_line("two")
    assert_equal 12, spi.payloads.length
    console.write_line("three")
    assert_equal "two", console.line_at(0)
    assert_equal "thre", console.line_at(1)
    assert_equal 18, spi.payloads.length
    assert_equal [0, 0, 0, 31], bytes_of(spi.payloads[-5])
    assert_equal [0, 0, 0, 7], bytes_of(spi.payloads[-3])
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
    assert_equal 24, spi.payloads.length
  end

  def test_reused_line_buffer_clears_old_glyphs
    spi = FakeSPI.new
    console = build_console(spi, :rows => 2, :cols => 1)

    console.write_line("A")
    first = bytes_of(spi.payloads[-1])
    console.write_line("")
    second = bytes_of(spi.payloads[-1])

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

  class FakeSPI
    attr_reader :payloads

    def initialize
      @payloads = []
    end

    def select
      yield self
    end

    def write(v)
      @payloads << (v.is_a?(String) ? v.dup : v)
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

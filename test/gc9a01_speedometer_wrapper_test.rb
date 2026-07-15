# Usage:
#   ruby test/gc9a01_speedometer_wrapper_test.rb

require "minitest/autorun"

class GC9A01Display
  class << self
    attr_reader :native_configure_args

    def _configure(*args)
      @native_configure_args = args
      true
    end
  end
end

class GC9A01Speedometer
  attr_reader :native_calls

  def _init(*args)
    @native_calls = [[:init, args]]
    true
  end

  def _render(*args)
    @native_calls << [:render, args]
    args[1]
  end

  def _demo_step(*args)
    @native_calls << [:demo_step, args]
    true
  end

  def _set_brightness(*args)
    @native_calls << [:brightness, args]
    args[1]
  end

  def _initialized(*args)
    @native_calls << [:initialized, args]
    true
  end
end

class GC9A01SimpleSpeedometer < GC9A01Speedometer
end

require_relative "../mrbgems/picoruby-gc9a01-speedometer/mrblib/gc9a01_speedometer"

class GC9A01SpeedometerWrapperTest < Minitest::Test
  CONFIG = [1, 10, 11, 9, 12, 13, 14, 20_000_000]

  def test_primary_and_secondary_configuration_include_display_index
    GC9A01Display.configure(*CONFIG)
    assert_equal [GC9A01Display::PRIMARY, *CONFIG],
                 GC9A01Display.native_configure_args

    GC9A01Display.configure_secondary(*CONFIG)
    assert_equal [GC9A01Display::SECONDARY, *CONFIG],
                 GC9A01Display.native_configure_args
  end

  def test_tachometer_defaults_to_primary_and_routes_all_native_calls
    meter = GC9A01Speedometer.new

    meter.render(23.4, 91.0, true, false)
    meter.brightness = 180
    assert_equal true, meter.initialized?

    assert_equal [
      [:init, [GC9A01Display::PRIMARY]],
      [:render, [GC9A01Display::PRIMARY, 23.4, 91.0, true, false]],
      [:brightness, [GC9A01Display::PRIMARY, 180]],
      [:initialized, [GC9A01Display::PRIMARY]]
    ], meter.native_calls
  end

  def test_tachometer_connection_indicators_default_to_disconnected
    meter = GC9A01Speedometer.new

    meter.render(0.0, 0.0)

    assert_equal [:render, [GC9A01Display::PRIMARY, 0.0, 0.0, false, false]],
                 meter.native_calls.last
  end

  def test_simple_speedometer_can_target_secondary_display
    meter = GC9A01SimpleSpeedometer.new(GC9A01Display::SECONDARY)

    meter.render(42.0)

    assert_equal [
      [:init, [GC9A01Display::SECONDARY]],
      [:render, [GC9A01Display::SECONDARY, 42.0]]
    ], meter.native_calls
  end
end

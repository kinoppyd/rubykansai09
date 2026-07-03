# GC9A01 speedometer demo for R2P2 on Raspberry Pi Pico / Pico 2.
#
# The firmware must include picoruby-gc9a01-speedometer. See:
# docs/picoruby/gc9a01_speedometer.md

require 'gc9a01_demo_config'

GC9A01DemoConfig.apply

puts "GC9A01 speedometer demo"
puts "Initializing LCD"
meter = GC9A01Speedometer.new
puts "LCD initialized"
meter.brightness = GC9A01DemoConfig::BRIGHTNESS

puts "Running gauge sweep"
sweep_rpm = 0
while sweep_rpm <= GC9A01DemoConfig::RPM_MAX
  meter.render(0, sweep_rpm)
  Machine.delay_ms(GC9A01DemoConfig::SWEEP_DELAY_MS)
  sweep_rpm += GC9A01DemoConfig::RPM_SWEEP_STEP
end

sweep_rpm = GC9A01DemoConfig::RPM_MAX
while sweep_rpm >= 0
  meter.render(0, sweep_rpm)
  Machine.delay_ms(GC9A01DemoConfig::SWEEP_DELAY_MS)
  sweep_rpm -= GC9A01DemoConfig::RPM_SWEEP_STEP
end

meter.render(0, 0)
Machine.delay_ms(GC9A01DemoConfig::SWEEP_PAUSE_MS)
puts "Starting animation"
meter.demo(GC9A01DemoConfig::FRAME_MS)

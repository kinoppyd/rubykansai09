# Standalone analog speedometer demo for R2P2 on Raspberry Pi Pico / Pico 2.
# The custom firmware already includes GC9A01SimpleSpeedometer.

require 'gc9a01_demo_config'

GC9A01DemoConfig.apply

puts "GC9A01 simple speedometer demo"
puts "Initializing LCD"
meter = GC9A01SimpleSpeedometer.new
puts "LCD initialized"
meter.brightness = GC9A01DemoConfig::BRIGHTNESS
puts "Rendering first frame"
meter.render(0)
puts "Starting animation"
meter.demo(GC9A01DemoConfig::FRAME_MS)

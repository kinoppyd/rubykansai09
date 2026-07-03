# Realistic standalone speedometer demo for R2P2 on Raspberry Pi Pico / Pico 2.
# The custom firmware must include picoruby-gc9a01-speedometer.

require 'gc9a01_demo_config'
require 'rng'

GC9A01DemoConfig.apply

def next_target_speed(speed)
  roll = rand(100)

  if speed < 2.0
    target = roll < 20 ? 0.0 : (8 + rand(20)).to_f
  elsif roll < 8
    target = 0.0
  elsif speed > 58.0
    target = (35 + rand(24)).to_f
  elsif roll < 50
    target = speed - (3 + rand(13))
  elsif roll < 92
    target = speed + (3 + rand(16))
  else
    target = (55 + rand(21)).to_f
  end

  target = 0.0 if target < 0.0
  if target > GC9A01DemoConfig::RIDING_MAX_SPEED
    target = GC9A01DemoConfig::RIDING_MAX_SPEED
  end
  target
end

puts "GC9A01 realistic speedometer demo"
puts "Initializing LCD"
meter = GC9A01SimpleSpeedometer.new
meter.brightness = GC9A01DemoConfig::BRIGHTNESS

puts "Running gauge sweep"
sweep_speed = 0
while sweep_speed <= GC9A01DemoConfig::SPEED_MAX
  meter.render(sweep_speed)
  Machine.delay_ms(GC9A01DemoConfig::SWEEP_DELAY_MS)
  sweep_speed += GC9A01DemoConfig::SPEED_SWEEP_STEP
end

sweep_speed = GC9A01DemoConfig::SPEED_MAX
while sweep_speed >= 0
  meter.render(sweep_speed)
  Machine.delay_ms(GC9A01DemoConfig::SWEEP_DELAY_MS)
  sweep_speed -= GC9A01DemoConfig::SPEED_SWEEP_STEP
end

speed = 0.0
target = 0.0
frames_until_target = 0
meter.render(speed)
Machine.delay_ms(GC9A01DemoConfig::SWEEP_PAUSE_MS)
puts "Starting animation"

loop do
  if frames_until_target <= 0
    target = next_target_speed(speed)
    # Hold each riding condition for roughly 3 to 7 seconds.
    frames_until_target = 90 + rand(121)
  end

  delta = target - speed
  if delta > 0.05
    # Acceleration becomes gentler at higher speeds.
    step = (speed < 25.0 ? 0.08 : 0.05) + rand(5) * 0.01
    speed += delta < step ? delta : step
  elsif delta < -0.05
    step = 0.10 + rand(7) * 0.01
    speed -= -delta < step ? -delta : step
  else
    speed = target
  end

  meter.render(speed)
  frames_until_target -= 1
  Machine.delay_ms(GC9A01DemoConfig::FRAME_MS)
end

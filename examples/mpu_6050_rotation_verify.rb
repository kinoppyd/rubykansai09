# Usage:
#   Copy this file to R2P2 and run it from irb or as an app.
#   Change I2C_UNIT, SDA_PIN, SCL_PIN, AXIS and DIRECTION for your wiring.
#
# Output:
#   EVENT lines show detected rotations.
#   SNAP lines show periodic diagnostic values.
#   Use gyro_x/y/z, angle_rad, phase_valid and dt_skipped to tune the setup.

require "i2c"
require "mpu_6050"
require "mpu_6050/rotation_detector"

I2C_UNIT = :RP2040_I2C1
SDA_PIN = 2
SCL_PIN = 3

AXIS = :y
DIRECTION = 0
MIN_PERIOD_MS = 120
GYRO_DEADBAND_DPS = 3.0

GYRO_RANGE_DPS = 2000
ACCEL_RANGE_G = 16
DLPF_CONFIG = 3
LOOP_SLEEP_MS = 5
REPORT_EVERY_MS = 1000
MAX_DT_MS = 50
ACCEL_PHASE_MIN_G = 0.25

def wait_ms(ms)
  if Object.const_defined?(:Machine) && Machine.respond_to?(:delay_ms)
    Machine.delay_ms(ms)
  else
    sleep_ms ms
  end
end

def abs_float(v)
  v < 0.0 ? -v : v
end

def detector_delta_angle(d)
  d.respond_to?(:delta_angle) ? d.delta_angle : 0.0
end

def detector_angle(d)
  d.respond_to?(:angle) ? d.angle : 0.0
end

def detector_gyro_dps(d)
  d.respond_to?(:gyro_dps) ? d.gyro_dps : 0.0
end

def detector_phase(d)
  d.respond_to?(:phase) ? d.phase : nil
end

def detector_phase_valid(d)
  d.respond_to?(:phase_valid?) ? d.phase_valid? : false
end

def detector_saturated(d)
  d.respond_to?(:saturated?) ? d.saturated? : false
end

def detector_dt_skipped(d)
  d.respond_to?(:dt_skipped?) ? d.dt_skipped? : false
end

def axis_hint(gx, gy, gz)
  if gx >= gy && gx >= gz
    :x
  elsif gy >= gz
    :y
  else
    :z
  end
end

i2c = I2C.new(
  unit: I2C_UNIT,
  frequency: 400_000,
  sda_pin: SDA_PIN,
  scl_pin: SCL_PIN
)

mpu = MPU6050.new(
  i2c,
  :gyro_range_dps => GYRO_RANGE_DPS,
  :accel_range_g => ACCEL_RANGE_G,
  :dlpf_config => DLPF_CONFIG
)

puts "MPU6050 rotation verify"
puts "Hold still"
wait_ms 1000
mpu.calibrate_gyro(200, 0)
puts "Spin now"

detector = mpu.rotation_detector(
  AXIS,
  MIN_PERIOD_MS,
  DIRECTION
)
detector.set_gyro_deadband_dps(GYRO_DEADBAND_DPS) if detector.respond_to?(:set_gyro_deadband_dps)
detector.set_max_dt_ms(MAX_DT_MS) if detector.respond_to?(:set_max_dt_ms)
detector.set_accel_phase_min_g(ACCEL_PHASE_MIN_G) if detector.respond_to?(:set_accel_phase_min_g)

puts "detector_setters"
puts detector.respond_to?(:set_gyro_deadband_dps)
puts detector.respond_to?(:set_max_dt_ms)
puts detector.respond_to?(:set_accel_phase_min_g)
puts "detector_debug_api"
puts detector.respond_to?(:angle)
puts detector.respond_to?(:phase_valid?)
puts detector.respond_to?(:dt_skipped?)
puts "configured_axis"
puts AXIS

next_report_ms = 0
max_gx = 0.0
max_gy = 0.0
max_gz = 0.0
max_delta = 0.0
sat_count = 0
dt_skip_count = 0

loop do
  sample = mpu.sample_now
  event = detector.update(sample)

  gx = abs_float(sample.gyro_x)
  gy = abs_float(sample.gyro_y)
  gz = abs_float(sample.gyro_z)
  d = abs_float(detector_delta_angle(detector))
  max_gx = gx if gx > max_gx
  max_gy = gy if gy > max_gy
  max_gz = gz if gz > max_gz
  max_delta = d if d > max_delta
  sat_count += 1 if detector_saturated(detector)
  dt_skip_count += 1 if detector_dt_skipped(detector)

  if event
    puts "EVENT"
    puts "count"
    puts event.count
    puts "time_ms"
    puts event.time_ms
    puts "gyro_dps"
    puts detector_gyro_dps(detector)
    puts "delta_angle_rad"
    puts detector_delta_angle(detector)
    puts "angle_rad"
    puts detector_angle(detector)
    puts "saturated"
    puts detector_saturated(detector)
    puts "dt_skipped"
    puts detector_dt_skipped(detector)
  end

  if sample.time_ms >= next_report_ms
    puts "SNAP"
    puts "time_ms"
    puts sample.time_ms
    puts "count"
    puts detector.count
    puts "dt_ms"
    puts sample.dt * 1000.0
    puts "gyro_x"
    puts sample.gyro_x
    puts "gyro_y"
    puts sample.gyro_y
    puts "gyro_z"
    puts sample.gyro_z
    puts "max_gyro_x"
    puts max_gx
    puts "max_gyro_y"
    puts max_gy
    puts "max_gyro_z"
    puts max_gz
    puts "axis_hint"
    puts axis_hint(max_gx, max_gy, max_gz)
    puts "gyro_dps"
    puts detector_gyro_dps(detector)
    puts "delta_angle_rad"
    puts detector_delta_angle(detector)
    puts "max_delta_angle_rad"
    puts max_delta
    puts "angle_rad"
    puts detector_angle(detector)
    puts "phase_rad"
    puts detector_phase(detector)
    puts "phase_valid"
    puts detector_phase_valid(detector)
    puts "saturated"
    puts detector_saturated(detector)
    puts "sat_count"
    puts sat_count
    puts "dt_skipped"
    puts detector_dt_skipped(detector)
    puts "dt_skip_count"
    puts dt_skip_count
    puts "accel_x"
    puts sample.accel_x
    puts "accel_y"
    puts sample.accel_y
    puts "accel_z"
    puts sample.accel_z
    next_report_ms = sample.time_ms + REPORT_EVERY_MS
  end

  wait_ms LOOP_SLEEP_MS
end

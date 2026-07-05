# Raspberry Pi Pico 2 W + MPU6050 cadence sensor for R2P2/PicoRuby.
# Wiring and sensor placement must match the constants below.

require "i2c"
require "machine"
require "mpu_6050"
require "mpu_6050/rotation_detector"
require "ble_transport/picoruby_peripheral"
require "mpu_6050_ble_csc"

DEVICE_NAME = "PicoRuby CSC"
SENSOR_MODE = :cadence

I2C_UNIT = :RP2040_I2C1
I2C_FREQUENCY = 400_000
SDA_PIN = 2
SCL_PIN = 3
MPU6050_ADDRESS = 0x68

GYRO_RANGE_DPS = 2_000
ACCEL_RANGE_G = 16
DLPF_CONFIG = 3
SAMPLE_PERIOD_US = 10_000
NOTIFY_PERIOD_MS = 1_000
CALIBRATION_SAMPLES = 200
CALIBRATION_WAIT_MS = 5

WHEEL_AXIS = nil
WHEEL_DIRECTION = 1
WHEEL_MIN_PERIOD_MS = 120
CRANK_AXIS = :x
CRANK_DIRECTION = 1
CRANK_MIN_PERIOD_MS = 250
SENSOR_LOCATION = 6 # Right Crank

DEBUG_LOG = false
STATUS_PERIOD_MS = 60_000
MAX_CONSECUTIVE_I2C_ERRORS = 3

raise "cadence-only configuration required" unless SENSOR_MODE == :cadence
raise "wheel axis must be disabled" unless WHEEL_AXIS.nil?
raise "crank axis is required" if CRANK_AXIS.nil?

ble = nil
begin
  i2c = I2C.new(
    unit: I2C_UNIT,
    frequency: I2C_FREQUENCY,
    sda_pin: SDA_PIN,
    scl_pin: SCL_PIN
  )
  mpu = MPU6050.new(
    i2c,
    :address => MPU6050_ADDRESS,
    :gyro_range_dps => GYRO_RANGE_DPS,
    :accel_range_g => ACCEL_RANGE_G,
    :dlpf_config => DLPF_CONFIG,
    :sample_interval_ms => SAMPLE_PERIOD_US / 1_000,
    :auto_configure => false
  )

  puts "MPU6050 identity check" if DEBUG_LOG
  mpu.verify_identity
  mpu.configure(:dlpf_config => DLPF_CONFIG)
  puts "Keep crank still during gyro calibration" if DEBUG_LOG
  mpu.calibrate_gyro(CALIBRATION_SAMPLES, CALIBRATION_WAIT_MS)

  ble = BLETransport::PicoRubyPeripheral.new
  sensor = MPU6050BLECSC.new(
    mpu,
    ble,
    DEVICE_NAME,
    WHEEL_AXIS,
    CRANK_AXIS,
    WHEEL_MIN_PERIOD_MS,
    CRANK_MIN_PERIOD_MS,
    NOTIFY_PERIOD_MS,
    SENSOR_LOCATION,
    WHEEL_DIRECTION,
    CRANK_DIRECTION
  )
  sensor.start
  ble.power_on

  next_sample_us = Machine.uptime_us
  last_status_ms = (next_sample_us / 1_000) & 0xffffffff
  max_loop_us = 0
  overruns = 0
  i2c_errors = 0
  consecutive_i2c_errors = 0

  loop do
    now_us = Machine.uptime_us
    remaining_us = next_sample_us - now_us
    while remaining_us > 0
      wait_ms = remaining_us / 1_000
      Machine.delay_ms(wait_ms) if wait_ms > 0
      now_us = Machine.uptime_us
      remaining_us = next_sample_us - now_us
    end

    loop_start_us = now_us
    now_ms = (now_us / 1_000) & 0xffffffff
    begin
      sensor.tick(now_ms)
      consecutive_i2c_errors = 0
    rescue IOError
      i2c_errors += 1
      consecutive_i2c_errors += 1
      raise if consecutive_i2c_errors >= MAX_CONSECUTIVE_I2C_ERRORS
    end
    ble.poll(now_ms)

    after_us = Machine.uptime_us
    loop_us = after_us - loop_start_us
    max_loop_us = loop_us if max_loop_us < loop_us
    next_sample_us += SAMPLE_PERIOD_US
    if next_sample_us < after_us
      overruns += 1
      next_sample_us = after_us + SAMPLE_PERIOD_US
    end

    status_elapsed = (now_ms - last_status_ms) & 0xffffffff
    if DEBUG_LOG && STATUS_PERIOD_MS <= status_elapsed
      puts "CSCP sensor status"
      puts sensor.service.crank_revolutions
      puts max_loop_us
      puts overruns
      puts i2c_errors
      puts ble.event_queue_dropped
      last_status_ms = now_ms
    end
  end
ensure
  ble.power_off if ble
end

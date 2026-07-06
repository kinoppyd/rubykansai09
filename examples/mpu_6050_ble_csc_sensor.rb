# Raspberry Pi Pico 2 W + MPU6050 cadence sensor for R2P2/PicoRuby.
# Wiring and sensor placement must match the constants below.

require "i2c"
require "machine"
require "mpu_6050"
require "mpu_6050/rotation_detector"
require "ble_transport/picoruby_peripheral"

DEVICE_NAME = "PicoRuby CSC"
CSC_FEATURE_CRANK = 2

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

CRANK_AXIS = :x
CRANK_DIRECTION = 1
CRANK_MIN_PERIOD_MS = 250
SENSOR_LOCATION = 6 # Right Crank

DEBUG_LOG = false
STATUS_PERIOD_MS = 60_000
MAX_CONSECUTIVE_I2C_ERRORS = 3

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

  crank = mpu.rotation_detector(
    CRANK_AXIS,
    CRANK_MIN_PERIOD_MS,
    CRANK_DIRECTION
  )
  ble = BLETransport::PicoRubyPeripheral.new
  ble.setup_csc(
    DEVICE_NAME,
    BLETransport.u16_le(CSC_FEATURE_CRANK),
    SENSOR_LOCATION
  )
  ble.power_on

  next_sample_us = Machine.uptime_us
  last_status_ms = (next_sample_us / 1_000) & 0xffffffff
  last_notify_ms = nil
  last_crank_count = 0
  crank_revolutions = 0
  crank_event_time = 0
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
      sample = mpu.sample(now_ms)
      event = crank.update(sample)
      if event
        crank_delta = event.count - last_crank_count
        last_crank_count = event.count
        crank_revolutions = (crank_revolutions + crank_delta) & 0xffff
        crank_event_time = BLETransport.csc_event_time_ticks(event.time_ms)
      end
      consecutive_i2c_errors = 0
    rescue IOError
      i2c_errors += 1
      consecutive_i2c_errors += 1
      raise if consecutive_i2c_errors >= MAX_CONSECUTIVE_I2C_ERRORS
    end
    ble.poll(now_ms)

    notify_elapsed = last_notify_ms.nil? ? NOTIFY_PERIOD_MS : ((now_ms - last_notify_ms) & 0xffffffff)
    if NOTIFY_PERIOD_MS <= notify_elapsed
      ble.notify_csc(0, 0, crank_revolutions, crank_event_time)
      last_notify_ms = now_ms
    end

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
      puts crank_revolutions
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

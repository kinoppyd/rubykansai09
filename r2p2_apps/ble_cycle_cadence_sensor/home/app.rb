# Dedicated cadence sensor app for R2P2/PicoRuby on Raspberry Pi Pico 2 W.

require "machine"
require "ble_cycle_packet"
require "ble_cycle_sensor/uart_peripheral"

DEVICE_NAME = "PRCad"
DEBUG_LOG = true
DEBUG_BLE = true

# Set false to verify the BLE path with generated 60 rpm data.
USE_MPU = true

I2C_UNIT = :RP2040_I2C1
I2C_FREQUENCY = 400_000
SDA_PIN = 2
SCL_PIN = 3

# Adjust these values after mounting the MPU-6050 on the crank.
AXIS = :y
DIRECTION = 0
MIN_PERIOD_MS = 120
GYRO_DEADBAND_DPS = 3.0
MAX_DT_MS = 50
ACCEL_PHASE_MIN_G = 0.25
CALIBRATION_SAMPLES = 200
CALIBRATION_WAIT_MS = 5

NOTIFY_PERIOD_MS = 500
FAKE_DELTA_ANGLE_MRAD = 3142
FULL_ROTATION_MRAD = 6283
MAX_CONSECUTIVE_I2C_ERRORS = 3

if USE_MPU
  require "i2c"
  require "mpu_6050"
  require "mpu_6050/rotation_detector"
end

def now_ms
  if Object.const_defined?(:Machine)
    return Machine.uptime_us / 1000 if Machine.respond_to?(:uptime_us)
    return Machine.board_millis if Machine.respond_to?(:board_millis)
  end
  0
end

def clamp_u16(v)
  v > 0xffff ? 0xffff : v
end

def interval_ms(now, last)
  return 0 if last.nil?
  clamp_u16((now - last) & 0xffffffff)
end

def status_value(sample_count, i2c_error_count)
  (sample_count & 0xff) | ((i2c_error_count & 0xff) << 8)
end

puts "BLE cadence sensor"
puts "sensor_role"
puts "cadence"
puts "mode"
puts(USE_MPU ? "mpu" : "fake")

mpu = nil
detector = nil

if USE_MPU
  i2c = I2C.new(
    unit: I2C_UNIT,
    frequency: I2C_FREQUENCY,
    sda_pin: SDA_PIN,
    scl_pin: SCL_PIN
  )
  mpu = MPU6050.new(i2c)
  puts "calibrating"
  mpu.calibrate_gyro(CALIBRATION_SAMPLES, CALIBRATION_WAIT_MS)
  detector = mpu.rotation_detector(
    AXIS,
    MIN_PERIOD_MS,
    DIRECTION,
    GYRO_DEADBAND_DPS,
    MAX_DT_MS,
    ACCEL_PHASE_MIN_G
  )
  puts "mpu_ready"
end

ble = BLECycleSensor::UARTPeripheral.new(DEVICE_NAME)
ble.debug = DEBUG_BLE
payload = BLECyclePacket.bytes(BLECyclePacket::SIZE)

sequence = 0
first_packet = true
last_send_ms = nil
delta_angle_mrad = 0.0
fake_total_angle_mrad = 0
total_revolutions = 0
sample_count = 0
i2c_error_count = 0
i2c_error_interval = 0
consecutive_i2c_errors = 0
interval_flags = 0
last_connected = false

ble.start do
  now = now_ms
  connected = ble.connected?
  if connected != last_connected
    puts "ble_connected"
    puts(connected ? 1 : 0)
    last_connected = connected
    first_packet = true if connected
    last_send_ms = nil if connected
    delta_angle_mrad = 0.0 if connected
  end

  if USE_MPU
    begin
      sample = mpu.sample(now)
      event = detector.update(sample)
      delta_angle_mrad += detector.delta_angle * 1000.0
      sample_count += 1
      interval_flags |= BLECyclePacket::FLAG_ROTATION_CHANGED if event
      interval_flags |= BLECyclePacket::FLAG_SATURATED if detector.saturated?
      interval_flags |= BLECyclePacket::FLAG_DT_SKIPPED if detector.dt_skipped?
      total_revolutions = detector.count
      consecutive_i2c_errors = 0
    rescue IOError
      i2c_error_count += 1
      i2c_error_interval += 1
      consecutive_i2c_errors += 1
      interval_flags |= BLECyclePacket::FLAG_I2C_ERROR
      raise if consecutive_i2c_errors >= MAX_CONSECUTIVE_I2C_ERRORS
    end
  else
    sample_count += 1
  end

  next unless connected

  elapsed = interval_ms(now, last_send_ms)
  next if !first_packet && elapsed < NOTIFY_PERIOD_MS

  flags = interval_flags | BLECyclePacket::FLAG_ANGLE_VALID
  flags |= BLECyclePacket::FLAG_FIRST if first_packet

  if USE_MPU
    angle_to_send = first_packet ? 0 : delta_angle_mrad.to_i
  else
    if first_packet
      angle_to_send = 0
    else
      fake_total_angle_mrad += FAKE_DELTA_ANGLE_MRAD
      total_revolutions = fake_total_angle_mrad / FULL_ROTATION_MRAD
      angle_to_send = FAKE_DELTA_ANGLE_MRAD
      flags |= BLECyclePacket::FLAG_ROTATION_CHANGED
    end
  end

  BLECyclePacket.encode_into(
    payload,
    flags,
    sequence,
    now,
    total_revolutions,
    angle_to_send,
    elapsed,
    status_value(sample_count, i2c_error_interval)
  )
  ble.write(payload)

  if DEBUG_LOG
    puts "TX"
    puts "sensor_role"
    puts "cadence"
    puts "seq"
    puts sequence
    puts "time_ms"
    puts now
    puts "total_rev"
    puts total_revolutions
    puts "delta_mrad"
    puts angle_to_send
    puts "interval_ms"
    puts elapsed
    puts "flags"
    puts flags
  end

  sequence = (sequence + 1) & 0xffff
  first_packet = false
  last_send_ms = now
  delta_angle_mrad = 0.0
  sample_count = 0
  i2c_error_interval = 0
  interval_flags = 0
end

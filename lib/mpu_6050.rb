# Usage:
#   require "mpu_6050"
#   require "mpu_6050/rotation_detector"
#   i2c = I2C.new(unit: :RP2040_I2C0, frequency: 400_000, sda_pin: 4, scl_pin: 5)
#   mpu = MPU6050.new(i2c, :gyro_range_dps => 500, :sample_interval_ms => 10)
#   mpu.calibrate_gyro
#   wheel = mpu.rotation_detector(:z, 120)
#   loop do
#     if event = wheel.update(mpu.sample)
#       puts event.count
#     end
#   end
# Copy both files: `mpu_6050.rb` and `mpu_6050/rotation_detector.rb`.

class MPU6050
  def initialize(i2c, o = nil)
    @i2c = i2c
    @ad = opt(o, :address, 0x68)
    @as = accel_scale(opt(o, :accel_range_g, 2))
    @gs = gyro_scale(opt(o, :gyro_range_dps, 250))
    @si = opt(o, :sample_interval_ms, 10)
    @gox = 0.0
    @goy = 0.0
    @goz = 0.0
    @time_ms = nil
    @dt = 0.0
    @lt = nil
    @ax = 0.0
    @ay = 0.0
    @az = 0.0
    @gx = 0.0
    @gy = 0.0
    @gz = 0.0
    configure(o) if opt(o, :auto_configure, true)
  end

  def time_ms
    @time_ms
  end

  def dt
    @dt
  end

  def accel_x
    @ax
  end

  def accel_y
    @ay
  end

  def accel_z
    @az
  end

  def gyro_x
    @gx
  end

  def gyro_y
    @gy
  end

  def gyro_z
    @gz
  end

  def configure(o = nil)
    w(0x6B, 1)
    w(0x19, opt(o, :sample_rate_divider, 7))
    w(0x1A, opt(o, :dlpf_config, 3))
    w(0x1B, gyro_config(@gs))
    w(0x1C, accel_config(@as))
    true
  end

  def sample(t = nil)
    t = now_ms if t.nil?
    @dt = @lt ? (t - @lt).to_f / 1000.0 : 0.0
    @time_ms = t
    @lt = t
    b = @i2c.read(@ad, 14, 0x3B)
    @ax = i16(b, 0) / @as
    @ay = i16(b, 2) / @as
    @az = i16(b, 4) / @as
    @gx = i16(b, 8) / @gs - @gox
    @gy = i16(b, 10) / @gs - @goy
    @gz = i16(b, 12) / @gs - @goz
    self
  end

  def calibrate_gyro(n = 200, wait_ms = 5)
    sx = 0.0
    sy = 0.0
    sz = 0.0
    n.times do
      b = @i2c.read(@ad, 14, 0x3B)
      sx += i16(b, 8) / @gs
      sy += i16(b, 10) / @gs
      sz += i16(b, 12) / @gs
      delay(wait_ms) if wait_ms && wait_ms > 0
    end
    @gox = sx / n
    @goy = sy / n
    @goz = sz / n
    self
  end

  def rotation_detector(axis = :z, min_ms = 120, direction = 0)
    MPU6050::RotationDetector.new(axis, min_ms, direction)
  end

  def opt(o, k, d)
    return d if o.nil?
    v = o[k]
    v.nil? ? d : v
  end

  def w(r, v)
    @i2c.write(@ad, r, v)
  end

  def i16(b, i)
    h = b.getbyte(i)
    l = b.getbyte(i + 1)
    v = ((h & 255) << 8) | (l & 255)
    v >= 32768 ? v - 65536 : v
  end

  def accel_scale(r)
    return 2048.0 if r == 16
    return 4096.0 if r == 8
    return 8192.0 if r == 4
    16384.0
  end

  def gyro_scale(r)
    return 16.4 if r == 2000
    return 32.8 if r == 1000
    return 65.5 if r == 500
    131.0
  end

  def accel_config(s)
    return 24 if s == 2048.0
    return 16 if s == 4096.0
    return 8 if s == 8192.0
    0
  end

  def gyro_config(s)
    return 24 if s == 16.4
    return 16 if s == 32.8
    return 8 if s == 65.5
    0
  end

  def now_ms
    @time_ms ? @time_ms + @si : 0
  end

  def delay(ms)
    nil
  end
end

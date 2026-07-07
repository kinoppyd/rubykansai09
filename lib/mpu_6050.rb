# Usage:
#   require "mpu_6050"
#   require "mpu_6050/rotation_detector"
#   i2c = I2C.new(unit: :RP2040_I2C0, frequency: 400_000, sda_pin: 4, scl_pin: 5)
#   mpu = MPU6050.new(i2c)
#   mpu.calibrate_gyro
#   wheel = mpu.rotation_detector(:z, 120, 1)
#   loop do
#     sample = mpu.sample_now
#     event = wheel.update(sample)
#     puts event.count if event
#   end
#
# Minimal MPU-6050/MPU-6500 driver for PicoRuby. sample returns self and exposes
# scalar accel_x/accel_y/accel_z and gyro_x/gyro_y/gyro_z readers to avoid
# allocating arrays or hashes while sampling.

class MPU6050
  def initialize(i2c, o = nil)
    @i2c = i2c
    @ad = opt(o, :address, 0x68)
    @as = accel_scale(opt(o, :accel_range_g, 16))
    @gs = gyro_scale(opt(o, :gyro_range_dps, 2000))
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
    @sat = false
    @gsat = false
    @sat_raw = opt(o, :accel_saturation_raw, 32000)
    @gsat_raw = opt(o, :gyro_saturation_raw, 32700)
    @sample_buffer = fixed_buffer(14)
    @identity_buffer = fixed_buffer(1)
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

  def accel_saturated?
    @sat
  end

  def gyro_saturated?
    @gsat
  end

  def verify_identity
    b = read_exact(1, 0x75)
    id = b.getbyte(0)
    return true if id == 0x68 || id == 0x70
    raise IOError, "unsupported MPU identity " + id.to_s
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
    b = read_exact(14, 0x3B)
    @dt = @lt ? (t - @lt).to_f / 1000.0 : 0.0
    @time_ms = t
    @lt = t
    rax = i16(b, 0)
    ray = i16(b, 2)
    raz = i16(b, 4)
    rgx = i16(b, 8)
    rgy = i16(b, 10)
    rgz = i16(b, 12)
    @sat = raw_abs(rax) >= @sat_raw || raw_abs(ray) >= @sat_raw || raw_abs(raz) >= @sat_raw
    @gsat = raw_abs(rgx) >= @gsat_raw || raw_abs(rgy) >= @gsat_raw || raw_abs(rgz) >= @gsat_raw
    @ax = rax / @as
    @ay = ray / @as
    @az = raz / @as
    @gx = rgx / @gs - @gox
    @gy = rgy / @gs - @goy
    @gz = rgz / @gs - @goz
    self
  end

  def sample_now
    sample(real_time_ms)
  end

  def calibrate_gyro(n = 200, wait_ms = 5)
    raise ArgumentError, "sample count must be positive" if n <= 0
    sx = 0.0
    sy = 0.0
    sz = 0.0
    n.times do
      b = read_exact(14, 0x3B)
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

  def rotation_detector(axis = :z, min_ms = 120, direction = 0, gyro_deadband_dps = 3.0, max_dt_ms = 250, accel_phase_min_g = 0.25)
    d = MPU6050::RotationDetector.new(axis, min_ms, direction)
    d.set_gyro_deadband_dps(gyro_deadband_dps) if d.respond_to?(:set_gyro_deadband_dps)
    d.set_max_dt_ms(max_dt_ms) if d.respond_to?(:set_max_dt_ms)
    d.set_accel_phase_min_g(accel_phase_min_g) if d.respond_to?(:set_accel_phase_min_g)
    d
  end

  def opt(o, k, d)
    return d if o.nil?
    v = o[k]
    v.nil? ? d : v
  end

  def w(r, v)
    @i2c.write(@ad, r, v)
  end

  def read_exact(n, r)
    if @i2c.respond_to?(:read_into)
      b = n == 14 ? @sample_buffer : @identity_buffer
      @i2c.read_into(@ad, b, r)
    else
      b = @i2c.read(@ad, n, r)
    end
    return b if b.is_a?(String) && b.bytesize >= n
    raise IOError, "MPU6050 short read"
  end

  def fixed_buffer(n)
    s = String.new
    i = 0
    while i < n
      s << 0
      i += 1
    end
    s
  end

  def i16(b, i)
    h = b.getbyte(i)
    l = b.getbyte(i + 1)
    v = ((h & 255) << 8) | (l & 255)
    v >= 32768 ? v - 65536 : v
  end

  def raw_abs(v)
    v < 0 ? -v : v
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

  def real_time_ms
    if Object.const_defined?(:Machine)
      return Machine.uptime_us / 1000 if Machine.respond_to?(:uptime_us)
      return Machine.board_millis if Machine.respond_to?(:board_millis)
    end
    now_ms
  end

  def delay(ms)
    if Object.const_defined?(:Machine) && Machine.respond_to?(:delay_ms)
      Machine.delay_ms(ms)
    elsif Kernel.respond_to?(:sleep_ms)
      sleep_ms ms
    else
      sleep(ms / 1000.0)
    end
  end
end

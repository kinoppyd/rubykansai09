# Usage:
#   require "mpu_6050"
#   require "mpu_6050/rotation_detector"
#   mpu = MPU6050.new(i2c)
#   detector = MPU6050::RotationDetector.new(:z, 120, 1)
#   detector.set_max_dt_ms(50)
#   loop do
#     event = detector.update(mpu.sample_now)
#     puts detector.delta_angle
#     puts event.count if event
#   end
#
# Detects full rotations around one axis. Gyro integration is used when the
# selected gyro axis is moving; accelerometer phase remains as a low-speed
# fallback. The sample object must provide time_ms, dt, accel_* and gyro_*.

class MPU6050
  class RotationDetector
    def initialize(axis = :z, min_ms = 120, direction = 0)
      @a = axis == :x || axis == 0 ? 0 : (axis == :y || axis == 1 ? 1 : 2)
      @min = min_ms
      @dir = direction == :positive || direction == 1 ? 1 : (direction == :negative || direction == -1 ? -1 : 0)
      @dead = 3.0
      @max_dt = 0.25
      @amin2 = 0.0625
      @count = 0
      @time_ms = nil
      @p = nil
      @phase = nil
      @phase_ok = false
      @delta = 0.0
      @gyro = 0.0
      @sat = false
      @gyro_sat = false
      @dt_skip = false
      @sum = 0.0
      @last = nil
    end

    def set_gyro_deadband_dps(v)
      @dead = v
      self
    end

    def set_max_dt_ms(v)
      @max_dt = v ? v / 1000.0 : 0.0
      self
    end

    def set_accel_phase_min_g(v)
      @amin2 = v * v
      self
    end

    def count
      @count
    end

    def time_ms
      @time_ms
    end

    def phase
      @phase
    end

    def phase_valid?
      @phase_ok
    end

    def delta_angle
      @delta
    end

    def angle
      @sum
    end

    def gyro_dps
      @gyro
    end

    def saturated?
      @sat || @gyro_sat
    end

    def gyro_saturated?
      @gyro_sat
    end

    def dt_skipped?
      @dt_skip
    end

    def update(s)
      t = s.time_ms
      @sat = accel_saturated_sample?(s)
      @gyro_sat = gyro_saturated_sample?(s)
      p = nil
      ad = 0.0

      if !@sat && accel_phase_ready?(s)
        p = accel_phase(s)
        @phase_ok = true
      else
        @phase_ok = false
        @p = nil
      end

      if p
        @phase = p
        if @p.nil?
          @p = p
        else
          ad = wrap(p - @p)
          @p = p
        end
      end

      d = gyro_delta(s)
      d = ad if d == 0.0 && !@dt_skip
      @delta = d
      return nil if d == 0.0
      @sum += d

      if @sum >= 6.0 && (@dir == 0 || @dir == 1)
        @sum -= 6.283185307179586
        pms = @last ? t - @last : nil
        return nil if pms && pms < @min
        @count += 1
        @time_ms = t
        @last = t
        return self
      end

      if @sum <= -6.0 && (@dir == 0 || @dir == -1)
        @sum += 6.283185307179586
        pms = @last ? t - @last : nil
        return nil if pms && pms < @min
        @count -= 1
        @time_ms = t
        @last = t
        return self
      end

      nil
    end

    def accel_phase(s)
      if @a == 0
        Math.atan2(s.accel_y, s.accel_z)
      elsif @a == 1
        Math.atan2(s.accel_z, s.accel_x)
      else
        Math.atan2(s.accel_x, s.accel_y)
      end
    end

    def gyro_delta(s)
      g = gyro_value(s)
      @gyro = g.nil? ? 0.0 : g
      @dt_skip = false
      dt = s.dt
      return 0.0 if dt.nil? || dt <= 0.0
      if @max_dt > 0.0 && dt > @max_dt
        @dt_skip = true
        return 0.0
      end
      return 0.0 if @gyro_sat
      return 0.0 if g.nil?
      ag = g < 0.0 ? -g : g
      return 0.0 if ag < @dead
      g * 0.017453292519943295 * dt
    end

    def gyro_value(s)
      if @a == 0
        s.gyro_x
      elsif @a == 1
        s.gyro_y
      else
        s.gyro_z
      end
    end

    def accel_phase_ready?(s)
      if @a == 0
        v = s.accel_y * s.accel_y + s.accel_z * s.accel_z
      elsif @a == 1
        v = s.accel_z * s.accel_z + s.accel_x * s.accel_x
      else
        v = s.accel_x * s.accel_x + s.accel_y * s.accel_y
      end
      v >= @amin2
    end

    def accel_saturated_sample?(s)
      s.respond_to?(:accel_saturated?) && s.accel_saturated?
    end

    def gyro_saturated_sample?(s)
      s.respond_to?(:gyro_saturated?) && s.gyro_saturated?
    end

    def wrap(v)
      v -= 6.283185307179586 if v > 3.141592653589793
      v += 6.283185307179586 if v < -3.141592653589793
      v
    end
  end
end

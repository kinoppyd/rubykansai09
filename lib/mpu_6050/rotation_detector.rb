# Usage:
#   require "mpu_6050"
#   require "mpu_6050/rotation_detector"
#   mpu = MPU6050.new(i2c)
#   detector = MPU6050::RotationDetector.new(:z, 120, 1)
#   loop do
#     event = detector.update(mpu.sample_now)
#     puts event.count if event
#   end
#
# Detects full rotations around one axis. Gyro integration is used when the
# selected gyro axis is moving; accelerometer phase remains as a low-speed
# fallback. The sample object must provide time_ms, dt, accel_* and gyro_*.

class MPU6050
  class RotationDetector
    def initialize(axis = :z, min_ms = 120, direction = 0, gyro_deadband_dps = 3.0)
      @a = axis == :x || axis == 0 ? 0 : (axis == :y || axis == 1 ? 1 : 2)
      @min = min_ms
      @dir = direction == :positive || direction == 1 ? 1 : (direction == :negative || direction == -1 ? -1 : 0)
      @dead = gyro_deadband_dps
      @count = 0
      @time_ms = nil
      @p = nil
      @sum = 0.0
      @last = nil
    end

    def count
      @count
    end

    def time_ms
      @time_ms
    end

    def update(s)
      t = s.time_ms
      p = accel_saturated_sample?(s) ? nil : accel_phase(s)
      ad = 0.0

      if p
        if @p.nil?
          @p = p
        else
          ad = wrap(p - @p)
          @p = p
        end
      end

      d = gyro_delta(s)
      d = ad if d == 0.0
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
      dt = s.dt
      return 0.0 if dt.nil? || dt <= 0.0
      g =
        if @a == 0
          s.gyro_x
        elsif @a == 1
          s.gyro_y
        else
          s.gyro_z
        end
      return 0.0 if g.nil?
      ag = g < 0.0 ? -g : g
      return 0.0 if ag < @dead
      g * 0.017453292519943295 * dt
    end

    def accel_saturated_sample?(s)
      s.respond_to?(:accel_saturated?) && s.accel_saturated?
    end

    def wrap(v)
      v -= 6.283185307179586 if v > 3.141592653589793
      v += 6.283185307179586 if v < -3.141592653589793
      v
    end
  end
end

# Usage:
#   require "mpu_6050"
#   require "mpu_6050/rotation_detector"
#   mpu = MPU6050.new(i2c)
#   detector = MPU6050::RotationDetector.new(:z, 120, 1)
#   loop do
#     event = detector.update(mpu.sample)
#     puts event.count if event
#   end
#
# Detects full rotations from the accelerometer phase around one axis. The
# sample object must provide time_ms and accel_x/accel_y/accel_z readers.

class MPU6050
  class RotationDetector
    def initialize(axis = :z, min_ms = 120, direction = 0)
      @a = axis == :x || axis == 0 ? 0 : (axis == :y || axis == 1 ? 1 : 2)
      @min = min_ms
      @dir = direction == :positive || direction == 1 ? 1 : (direction == :negative || direction == -1 ? -1 : 0)
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
      p =
        if @a == 0
          Math.atan2(s.accel_y, s.accel_z)
        elsif @a == 1
          Math.atan2(s.accel_z, s.accel_x)
        else
          Math.atan2(s.accel_x, s.accel_y)
        end

      if @p.nil?
        @p = p
        return nil
      end

      d = p - @p
      d -= 6.283185307179586 if d > 3.141592653589793
      d += 6.283185307179586 if d < -3.141592653589793
      @p = p
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
  end
end

# Converts BLE cycle packets into speed values for host-side logging/display.

module BLECycleHost
  class SpeedEstimator
    TWO_PI = 6.283185307179586
    DEFAULT_ZERO_DELTA_STOP_COUNT = 1

    attr_reader :speed_kmh
    attr_reader :zero_delta_count

    def initialize(wheel_circumference_mm = 2105,
                   zero_delta_stop_count = DEFAULT_ZERO_DELTA_STOP_COUNT,
                   smoothing_alpha = 1.0)
      @circumference_m = wheel_circumference_mm / 1000.0
      @zero_delta_stop_count = zero_delta_stop_count
      @smoothing_alpha = smoothing_alpha
      @speed_kmh = 0.0
      @zero_delta_count = 0
    end

    def update(packet)
      interval = packet.interval_ms
      if interval.nil? || interval <= 0
        stop!
        return false
      end

      rotations = packet.delta_angle_mrad / 1000.0 / TWO_PI
      if rotations == 0.0
        @zero_delta_count += 1
        stop! if @zero_delta_count >= @zero_delta_stop_count
        return true
      end

      @zero_delta_count = 0
      seconds = interval / 1000.0
      distance_m = rotations * @circumference_m
      speed = distance_m / seconds * 3.6

      @speed_kmh = smooth(@speed_kmh, absolute(speed))
      true
    end

    def stop!
      @speed_kmh = 0.0
      true
    end

    private

    def smooth(previous, value)
      alpha = @smoothing_alpha
      return value if alpha.nil? || alpha >= 1.0 || alpha <= 0.0
      previous + ((value - previous) * alpha)
    end

    def absolute(value)
      value < 0.0 ? -value : value
    end
  end
end

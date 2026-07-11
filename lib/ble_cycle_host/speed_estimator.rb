# Converts BLE cycle packets into speed values for host-side logging/display.

module BLECycleHost
  class SpeedEstimator
    TWO_PI = 6.283185307179586
    DEFAULT_TIMEOUT_MS = 1500
    DEFAULT_ZERO_DELTA_STOP_COUNT = 1

    attr_reader :speed_kmh
    attr_reader :wheel_rotations
    attr_reader :last_update_ms
    attr_reader :last_sequence
    attr_reader :last_gap
    attr_reader :gap_count
    attr_reader :zero_delta_count

    def initialize(wheel_circumference_mm = 2105,
                   timeout_ms = DEFAULT_TIMEOUT_MS,
                   zero_delta_stop_count = DEFAULT_ZERO_DELTA_STOP_COUNT,
                   smoothing_alpha = 1.0)
      @circumference_m = wheel_circumference_mm / 1000.0
      @timeout_ms = timeout_ms
      @zero_delta_stop_count = zero_delta_stop_count
      @smoothing_alpha = smoothing_alpha
      @speed_kmh = 0.0
      @wheel_rotations = 0.0
      @last_update_ms = nil
      @last_sequence = nil
      @last_gap = 0
      @gap_count = 0
      @zero_delta_count = 0
    end

    def update(packet, now_ms = nil)
      @last_update_ms = now_ms if now_ms
      check_sequence(packet.sequence)

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

      @wheel_rotations = rotations
      @speed_kmh = smooth(@speed_kmh, absolute(speed))
      true
    end

    def tick(now_ms)
      return false if @last_update_ms.nil?
      return false if @timeout_ms.nil? || @timeout_ms <= 0
      elapsed = (now_ms - @last_update_ms) & 0xffffffff
      return false if elapsed < @timeout_ms
      return false if stopped?

      stop!
      true
    end

    def stopped?
      @speed_kmh == 0.0 && @wheel_rotations == 0.0
    end

    def stop!
      @speed_kmh = 0.0
      @wheel_rotations = 0.0
      true
    end

    private

    def check_sequence(seq)
      if @last_sequence
        expected = (@last_sequence + 1) & 0xffff
        @last_gap = (seq - expected) & 0xffff
        @gap_count += 1 if @last_gap != 0
      else
        @last_gap = 0
      end
      @last_sequence = seq
    end

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

# Converts cadence-sensor rotation packets into crank revolutions per minute.

module BLECycleHost
  class CadenceEstimator
    TWO_PI = 6.283185307179586
    DEFAULT_ZERO_DELTA_STOP_COUNT = 1

    attr_reader :cadence_rpm
    attr_reader :duplicate_count
    attr_reader :zero_delta_count

    def initialize(zero_delta_stop_count = DEFAULT_ZERO_DELTA_STOP_COUNT,
                   smoothing_alpha = 1.0)
      @zero_delta_stop_count = zero_delta_stop_count
      @smoothing_alpha = smoothing_alpha
      @cadence_rpm = 0.0
      @last_sequence = nil
      @duplicate_count = 0
      @zero_delta_count = 0
    end

    def update(packet)
      return false unless accept_sequence?(packet.sequence)

      if first_packet?(packet) || packet.interval_ms.nil? || packet.interval_ms <= 0
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
      minutes = packet.interval_ms / 60_000.0
      rpm = rotations / minutes
      @cadence_rpm = smooth(@cadence_rpm, absolute(rpm))
      true
    end

    def stop!
      @cadence_rpm = 0.0
      true
    end

    private

    def accept_sequence?(sequence)
      if @last_sequence
        if sequence == @last_sequence
          @duplicate_count += 1
          return false
        end
      end
      @last_sequence = sequence
      true
    end

    def first_packet?(packet)
      (packet.flags & BLECyclePacket::FLAG_FIRST) != 0
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

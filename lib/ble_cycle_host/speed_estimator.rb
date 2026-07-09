# Converts BLE cycle packets into speed values for host-side logging/display.

module BLECycleHost
  class SpeedEstimator
    TWO_PI = 6.283185307179586

    attr_reader :speed_kmh
    attr_reader :cadence_rpm
    attr_reader :wheel_rotations

    def initialize(wheel_circumference_mm = 2105)
      @circumference_m = wheel_circumference_mm / 1000.0
      @speed_kmh = 0.0
      @cadence_rpm = 0.0
      @wheel_rotations = 0.0
    end

    def update(packet)
      interval = packet.interval_ms
      if interval.nil? || interval <= 0
        @speed_kmh = 0.0
        @cadence_rpm = 0.0
        @wheel_rotations = 0.0
        return false
      end

      rotations = packet.delta_angle_mrad / 1000.0 / TWO_PI
      seconds = interval / 1000.0
      distance_m = rotations * @circumference_m
      speed = distance_m / seconds * 3.6
      rpm = rotations * 60.0 / seconds

      @wheel_rotations = rotations
      @speed_kmh = speed < 0.0 ? -speed : speed
      @cadence_rpm = rpm < 0.0 ? -rpm : rpm
      true
    end
  end
end

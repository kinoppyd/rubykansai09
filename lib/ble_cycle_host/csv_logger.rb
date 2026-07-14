# Writes the latest cycle-computer values to sequential CSV files.

module BLECycleHost
  class CSVLogger
    DEFAULT_DIRECTORY = "/home/logs"
    DEFAULT_INTERVAL_MS = 1_000
    HEADER = "timestamp,speed_kmh,cadence_rpm\n"

    attr_reader :path
    attr_reader :row_count

    def initialize(directory = DEFAULT_DIRECTORY,
                   interval_ms = DEFAULT_INTERVAL_MS,
                   clock = Time)
      @directory = directory
      @interval_ms = interval_ms
      @clock = clock
      @last_write_ms = nil
      @row_count = 0
      @closed = false

      Dir.mkdir(@directory) unless Dir.exist?(@directory)
      @path = next_log_path
      @file = File.open(@path, "w")
      @file.write(HEADER)
      @file.fsync
    end

    def write_if_due(now_ms, connected, speed_kmh, cadence_rpm)
      return false if @closed || !connected
      if @last_write_ms
        elapsed = (now_ms - @last_write_ms) & 0xffffffff
        return false if elapsed < @interval_ms
      end

      @file.write(
        @clock.now.to_s,
        ",",
        decimal_2(speed_kmh),
        ",",
        decimal_2(cadence_rpm),
        "\n"
      )
      @file.fsync
      @last_write_ms = now_ms
      @row_count += 1
      true
    end

    def close
      return if @closed
      @file.close
      @closed = true
      nil
    end

    private

    def next_log_path
      maximum = -1
      directory = Dir.open(@directory)
      begin
        while entry = directory.read
          sequence = sequence_from(entry)
          maximum = sequence if sequence && maximum < sequence
        end
      ensure
        directory.close
      end
      "#{@directory}/#{padded_sequence(maximum + 1)}.csv"
    end

    def sequence_from(filename)
      length = filename.length
      return nil if length < 8
      stem_length = length - 4
      return nil unless filename[stem_length, 4] == ".csv"

      index = 0
      while index < stem_length
        byte = filename.getbyte(index)
        return nil unless byte && 48 <= byte && byte <= 57
        index += 1
      end
      filename[0, stem_length].to_i
    end

    def padded_sequence(sequence)
      value = sequence.to_s
      value = "0#{value}" while value.length < 4
      value
    end

    def decimal_2(value)
      negative = value < 0.0
      absolute = negative ? -value : value
      scaled = (absolute * 100.0 + 0.5).to_i
      fraction = scaled % 100
      fraction_text = fraction < 10 ? "0#{fraction}" : fraction.to_s
      "#{negative ? '-' : ''}#{scaled / 100}.#{fraction_text}"
    end
  end
end

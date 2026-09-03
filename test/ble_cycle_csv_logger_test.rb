# Usage:
#   ruby -Ilib test/ble_cycle_csv_logger_test.rb

require "minitest/autorun"
require "tmpdir"
require "ble_cycle_host/csv_logger"

class BLECycleCSVLoggerTest < Minitest::Test
  def test_creates_directory_and_starts_at_zero
    Dir.mktmpdir do |root|
      directory = File.join(root, "logs")
      logger = BLECycleHost::CSVLogger.new(directory, 1_000, FakeClock.new)

      assert_equal true, Dir.exist?(directory)
      assert_equal File.join(directory, "0000.csv"), logger.path
      logger.close
      assert_equal [BLECycleHost::CSVLogger::HEADER], File.readlines(logger.path)
    end
  end

  def test_uses_the_sequence_after_the_largest_csv_filename
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "0002.csv"), "old")
      File.write(File.join(directory, "0010.csv"), "old")
      File.write(File.join(directory, "9999.txt"), "ignored")
      File.write(File.join(directory, "latest.csv"), "ignored")

      logger = BLECycleHost::CSVLogger.new(directory, 1_000, FakeClock.new)

      assert_equal File.join(directory, "0011.csv"), logger.path
      logger.close
    end
  end

  def test_writes_latest_values_once_per_second_after_connection
    Dir.mktmpdir do |directory|
      clock = FakeClock.new("2026-07-14 10:00:00 +0900",
                            "2026-07-14 10:00:01 +0900")
      logger = BLECycleHost::CSVLogger.new(directory, 1_000, clock)

      assert_equal false, logger.write_if_due(100, false, 1.0, 2.0)
      assert_equal true, logger.write_if_due(200, true, 12.345, 89.014)
      assert_equal false, logger.write_if_due(1_199, true, 20.0, 100.0)
      assert_equal true, logger.write_if_due(1_200, true, 23.456, 91.236)
      logger.close

      assert_equal [
        "timestamp,speed_kmh,cadence_rpm\n",
        "2026-07-14 10:00:00 +0900,12.35,89.01\n",
        "2026-07-14 10:00:01 +0900,23.46,91.24\n"
      ], File.readlines(logger.path)
      assert_equal 2, logger.row_count
    end
  end

  class FakeClock
    FakeTime = Struct.new(:text) do
      def to_s
        text
      end
    end

    def initialize(*values)
      @values = values
      @index = 0
    end

    def now
      text = @values[@index] || "1970-01-01 00:00:00 +0000"
      @index += 1
      FakeTime.new(text)
    end
  end
end

# frozen_string_literal: true

# Run with:
#   ruby -Ilib test/ble_cycle_advertising_report_test.rb

require "minitest/autorun"
require "ble_cycle_host/advertising_report"

class BLECycleAdvertisingReportTest < Minitest::Test
  def test_parses_raw_hci_le_advertising_report
    packet = raw_le_advertising_report(
      address_bytes: [0xde, 0xa7, 0x0b, 0x9e, 0xa2, 0x88],
      data: ad_structure(0x01, "\x06") +
            ad_structure(0x09, "PRCycle") +
            ad_structure(0x07, uuid_le("6b3f0001-7a2d-4f6b-9af0-5c1a85f3d701")),
      rssi: -59
    )

    reports = []
    handled = BLECycleHost::AdvertisingReport.each(packet) { |report| reports << report }

    assert_equal true, handled
    assert_equal 1, reports.length
    assert_equal "PRCycle", reports[0].reports[:complete_local_name]
    assert_equal true, reports[0].name_include?("PRCycle")
    assert_equal "88:A2:9E:0B:A7:DE", reports[0].address.bytes.map { |b| "%02X" % b }.join(":")
    assert_equal "88:A2:9E:0B:A7:DE", reports[0].address_string
    assert_equal true, reports[0].address_include?("88:A2:9E:0B:A7:DE")
    assert_equal(-59, reports[0].rssi)
    assert_equal 30, reports[0].data_length
    assert_equal 16, reports[0].reports[:complete_list_128_bit_service_class_uuids].bytesize
  end

  private

  def raw_le_advertising_report(address_bytes:, data:, rssi:)
    params = [0x02, 0x01, 0x00, 0x00].pack("C*")
    params << address_bytes.pack("C*")
    params << [data.bytesize].pack("C")
    params << data
    params << [rssi & 0xff].pack("C")
    [0x3e, params.bytesize].pack("C*") + params
  end

  def ad_structure(type, value)
    [value.bytesize + 1, type].pack("C*") + value
  end

  def uuid_le(uuid)
    hex = uuid.delete("-")
    bytes = []
    0.step(hex.length - 2, 2) { |i| bytes << hex[i, 2].to_i(16) }
    bytes.reverse.pack("C*")
  end
end

# BLE scan diagnostic app for R2P2/PicoRuby on Raspberry Pi Pico 2 W.
# Temporarily copy this to /home/app.rb on the host Pico to verify that
# advertising reports are received before testing BLE::UART connection logic.

require "ble"
require "ble_cycle_host/advertising_report"

TARGET_NAME = "PRCycle"
TARGET_ADDRESS = "88:A2:9E:0B:A7:DE"
SCAN_INTERVAL = 0x60
SCAN_WINDOW = 0x30
STATUS_EVERY_HEARTBEATS = 5

class CycleScanDebug < BLE
  def initialize
    super(:central)
    @state = :TC_OFF
    @report_count = 0
    @target_count = 0
    @heartbeat_count = 0
    @unknown_count = 0
  end

  def run
    hci_power_control(HCI_POWER_ON)
    loop do
      while (packet = pop_packet)
        packet_callback(packet)
      end
      while pop_heartbeat
        heartbeat_callback
      end
      sleep_ms POLLING_UNIT_MS
    end
  ensure
    hci_power_control(HCI_POWER_OFF)
  end

  def packet_callback(packet)
    event_type = packet.getbyte(0)
    case event_type
    when BTSTACK_EVENT_STATE
      return unless packet.getbyte(2) == HCI_STATE_WORKING
      puts "scan_debug_up"
      puts Utils.bd_addr_to_str(gap_local_bd_addr)
      set_scan_params(:passive, SCAN_INTERVAL, SCAN_WINDOW)
      start_scan
      @state = :TC_W4_SCAN_RESULT
      puts "scan_started"
    when GAP_EVENT_ADVERTISING_REPORT
      print_advertising_reports(packet)
    when HCI_EVENT_LE_META
      if packet.getbyte(2) == BLECycleHost::AdvertisingReport::HCI_SUBEVENT_LE_ADVERTISING_REPORT
        print_advertising_reports(packet)
        return
      end
      puts "le_meta"
      puts packet.getbyte(2)
    else
      @unknown_count += 1
      if @unknown_count <= 10
        puts "event"
        puts event_type
      end
    end
  end

  def print_advertising_reports(packet)
    BLECycleHost::AdvertisingReport.each(packet) do |report|
      @report_count += 1
      name = report.reports[:complete_local_name] || report.reports[:shortened_local_name] || ""
      service128 = report.reports[:complete_list_128_bit_service_class_uuids] ||
                   report.reports[:incomplete_list_128_bit_service_class_uuids]
      name_match = report.name_include?(TARGET_NAME)
      address_match = report.address_include?(TARGET_ADDRESS)
      @target_count += 1 if name_match || address_match

      puts "adv_report"
      puts "count"
      puts @report_count
      puts "addr"
      puts Utils.bd_addr_to_str(report.address)
      puts "rssi"
      puts report.rssi
      puts "name"
      puts name
      puts "event_type"
      puts report.event_type
      puts "data_len"
      puts report.data_length
      puts "connectable"
      puts(report.connectable? ? 1 : 0)
      puts "scan_response"
      puts(report.scan_response? ? 1 : 0)
      puts "address_match"
      puts(address_match ? 1 : 0)
      puts "name_match"
      puts(name_match ? 1 : 0)
      puts "service128_len"
      puts(service128 ? service128.bytesize : 0)
    end
  end

  def heartbeat_callback
    @heartbeat_count += 1
    if (@heartbeat_count % STATUS_EVERY_HEARTBEATS) == 0
      puts "scan_status"
      puts "state"
      puts @state
      puts "reports"
      puts @report_count
      puts "targets"
      puts @target_count
      start_scan if @state == :TC_W4_SCAN_RESULT
    end
  end
end

puts "BLE cycle scan debug"
puts "target_name"
puts TARGET_NAME
puts "target_address"
puts TARGET_ADDRESS

scanner = CycleScanDebug.new
scanner.run

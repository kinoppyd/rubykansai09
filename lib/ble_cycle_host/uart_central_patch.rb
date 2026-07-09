# Runtime patch for PicoRuby BLE::UART central used by the cycle demo.
#
# Upstream BLE::UART central only connects when the custom 128-bit service UUID
# is present in the advertising report. During bring-up, also accepting the
# hard-coded device name gives us a useful fallback and clearer serial logs.

require "ble"
require "ble_cycle_host/advertising_report"

class BLE
  class UART < BLE
    HCI_EVENT_META_GAP = 0xE7
    GAP_SUBEVENT_LE_CONNECTION_COMPLETE = 0x08

    def cycle_target_name=(name)
      @cycle_target_name = name
    end

    def cycle_target_address=(address)
      @cycle_target_address = address
    end

    def cycle_scan_debug=(value)
      @cycle_scan_debug = value
      @cycle_scan_report_count = 0
    end

    def cycle_scan_report_count
      @cycle_scan_report_count || 0
    end

    def cycle_central_state
      @uart_central_state
    end

    private

    def _central_packet_callback(event_packet)
      event_type = event_packet.getbyte(0)
      return unless event_type
      case event_type
      when BTSTACK_EVENT_STATE
        return unless event_packet.getbyte(2) == HCI_STATE_WORKING
        debug_puts "UART Central up on: `#{Utils.bd_addr_to_str(gap_local_bd_addr)}`"
        set_scan_params(:passive, 0x30, 0x30)
        start_scan
        @uart_central_state = :TC_W4_SCAN_RESULT
        debug_puts "Scan started"

      when HCI_EVENT_DISCONNECTION_COMPLETE
        debug_puts "Disconnected, re-scanning"
        _central_reset
        set_scan_params(:passive, 0x30, 0x30)
        start_scan
        @uart_central_state = :TC_W4_SCAN_RESULT

      when GAP_EVENT_ADVERTISING_REPORT
        return unless @uart_central_state == :TC_W4_SCAN_RESULT
        _cycle_handle_advertising_packet(event_packet)

      when HCI_EVENT_LE_META
        if event_packet.getbyte(2) == ::BLECycleHost::AdvertisingReport::HCI_SUBEVENT_LE_ADVERTISING_REPORT
          return unless @uart_central_state == :TC_W4_SCAN_RESULT
          _cycle_handle_advertising_packet(event_packet)
          return
        end
        return unless event_packet.getbyte(2) == HCI_SUBEVENT_LE_CONNECTION_COMPLETE
        return unless @uart_central_state == :TC_W4_CONNECT
        _cycle_handle_connection_complete(event_packet)

      when HCI_EVENT_META_GAP
        return unless event_packet.getbyte(2) == GAP_SUBEVENT_LE_CONNECTION_COMPLETE
        return unless @uart_central_state == :TC_W4_CONNECT
        _cycle_handle_connection_complete(event_packet)

      when GATT_EVENT_QUERY_COMPLETE..GATT_EVENT_LONG_CHARACTERISTIC_VALUE_QUERY_RESULT
        _central_handle_gatt_event(event_type, event_packet)

      when GATT_EVENT_NOTIFICATION
        value_handle = Utils.little_endian_to_int16(event_packet.byteslice(4, 2))
        return unless value_handle == @peer_tx_handle
        value_length = Utils.little_endian_to_int16(event_packet.byteslice(6, 2))
        value = event_packet.byteslice(8, value_length)
        @rx_buffer << value if value
      end
    end

    def _cycle_handle_connection_complete(event_packet)
      status = event_packet.getbyte(3) || 0
      if status != 0
        debug_puts "Connection failed"
        debug_puts "status"
        debug_puts status
        _central_reset
        set_scan_params(:passive, 0x30, 0x30)
        start_scan
        @uart_central_state = :TC_W4_SCAN_RESULT
        return
      end

      @conn_handle = Utils.little_endian_to_int16(event_packet.byteslice(4, 2))
      debug_puts "Connected. Handle: #{sprintf('0x%04X', @conn_handle)}"
      discover_primary_services(@conn_handle)
      @uart_central_state = :TC_W4_SERVICE_RESULT
    end

    def _cycle_handle_advertising_packet(event_packet)
      ::BLECycleHost::AdvertisingReport.each(event_packet) do |adv_report|
        @cycle_scan_report_count = (@cycle_scan_report_count || 0) + 1
        service_data = adv_report.reports[:complete_list_128_bit_service_class_uuids] ||
                       adv_report.reports[:incomplete_list_128_bit_service_class_uuids]
        service_match = service_data && service_data.include?(@service_uuid_bin)
        name_match = @cycle_target_name && adv_report.name_include?(@cycle_target_name)
        address_match = @cycle_target_address && adv_report.address_include?(@cycle_target_address)
        if service_match || name_match || address_match
          unless adv_report.connectable?
            debug_puts "Matched non-connectable advertising report"
            debug_puts "addr"
            debug_puts Utils.bd_addr_to_str(adv_report.address)
            debug_puts "event_type"
            debug_puts adv_report.event_type
            debug_puts "data_len"
            debug_puts adv_report.data_length
            return
          end
          debug_puts "Found cycle UART device"
          debug_puts "addr"
          debug_puts Utils.bd_addr_to_str(adv_report.address)
          debug_puts "event_type"
          debug_puts adv_report.event_type
          debug_puts "data_len"
          debug_puts adv_report.data_length
          debug_puts "address_match"
          debug_puts(address_match ? 1 : 0)
          debug_puts "name_match"
          debug_puts(name_match ? 1 : 0)
          debug_puts "service_match"
          debug_puts(service_match ? 1 : 0)
          stop_scan
          err = gap_connect(adv_report.address, adv_report.address_type_code)
          debug_puts "gap_connect"
          debug_puts err
          @uart_central_state = :TC_W4_CONNECT if err == 0
          return
        elsif @cycle_scan_debug && (@cycle_scan_report_count % 50 == 0)
          debug_puts "scan_reports"
          debug_puts @cycle_scan_report_count
        end
      end
    end
  end
end

# Runtime patch for PicoRuby BLE::UART central used by the cycle demo.
#
# Upstream BLE::UART central only connects when the custom 128-bit service UUID
# is present in the advertising report. During bring-up, also accepting the
# hard-coded device name gives us a useful fallback and clearer serial logs.

require "ble"
require "ble_cycle_host/advertising_report"

class BLE
  class UART < BLE
    HCI_EVENT_COMMAND_COMPLETE = 0x0E
    HCI_EVENT_COMMAND_STATUS = 0x0F
    HCI_EVENT_META_GAP = 0xE7
    HCI_SUBEVENT_LE_ENHANCED_CONNECTION_COMPLETE_V1 = 0x0A
    HCI_SUBEVENT_LE_ENHANCED_CONNECTION_COMPLETE_V2 = 0x29
    GAP_SUBEVENT_LE_CONNECTION_COMPLETE = 0x08
    HCI_OPCODE_HCI_LE_SET_SCAN_ENABLE = 0x200C
    HCI_OPCODE_HCI_LE_CREATE_CONNECTION = 0x200D

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
        _cycle_debug_connect_event(event_packet) if @uart_central_state == :TC_W4_CONNECT
        debug_puts "Disconnected, re-scanning"
        _central_reset
        set_scan_params(:passive, 0x30, 0x30)
        start_scan
        @uart_central_state = :TC_W4_SCAN_RESULT

      when HCI_EVENT_COMMAND_COMPLETE
        _cycle_handle_command_complete(event_packet) if @uart_central_state == :TC_W4_CONNECT

      when HCI_EVENT_COMMAND_STATUS
        _cycle_handle_command_status(event_packet) if @uart_central_state == :TC_W4_CONNECT

      when GAP_EVENT_ADVERTISING_REPORT
        return unless @uart_central_state == :TC_W4_SCAN_RESULT
        _cycle_handle_advertising_packet(event_packet)

      when HCI_EVENT_LE_META
        if event_packet.getbyte(2) == ::BLECycleHost::AdvertisingReport::HCI_SUBEVENT_LE_ADVERTISING_REPORT
          return unless @uart_central_state == :TC_W4_SCAN_RESULT
          _cycle_handle_advertising_packet(event_packet)
          return
        end
        subevent = event_packet.getbyte(2)
        return unless subevent == HCI_SUBEVENT_LE_CONNECTION_COMPLETE ||
                      subevent == HCI_SUBEVENT_LE_ENHANCED_CONNECTION_COMPLETE_V1 ||
                      subevent == HCI_SUBEVENT_LE_ENHANCED_CONNECTION_COMPLETE_V2
        return unless @uart_central_state == :TC_W4_CONNECT
        _cycle_handle_connection_complete(event_packet)

      when HCI_EVENT_META_GAP
        _cycle_debug_connect_event(event_packet) if @uart_central_state == :TC_W4_CONNECT
        return unless event_packet.getbyte(2) == GAP_SUBEVENT_LE_CONNECTION_COMPLETE
        return unless @uart_central_state == :TC_W4_CONNECT
        _cycle_handle_connection_complete(event_packet)

      when GATT_EVENT_QUERY_COMPLETE..GATT_EVENT_LONG_CHARACTERISTIC_VALUE_QUERY_RESULT
        _central_handle_gatt_event(event_type, event_packet)

      when GATT_EVENT_NOTIFICATION
        value_handle = Utils.little_endian_to_int16(event_packet.byteslice(8, 2))
        return unless value_handle == @peer_tx_handle
        value_length = Utils.little_endian_to_int16(event_packet.byteslice(10, 2))
        value = event_packet.byteslice(12, value_length)
        @rx_buffer << value if value
      end
    end

    def _central_handle_gatt_event(event_type, event_packet)
      case @uart_central_state
      when :TC_W4_SERVICE_RESULT
        case event_type
        when GATT_EVENT_SERVICE_QUERY_RESULT
          if event_packet.byteslice(12, 16) == @service_uuid_bin
            @nus_start_handle = Utils.little_endian_to_int16(event_packet.byteslice(8, 2))
            @nus_end_handle   = Utils.little_endian_to_int16(event_packet.byteslice(10, 2))
            debug_puts "NUS service found. Handles: #{@nus_start_handle}..#{@nus_end_handle}"
          elsif @cycle_scan_debug
            debug_puts "GATT service skipped"
            debug_puts "start"
            debug_puts Utils.little_endian_to_int16(event_packet.byteslice(8, 2))
            debug_puts "end"
            debug_puts Utils.little_endian_to_int16(event_packet.byteslice(10, 2))
          end
        when GATT_EVENT_QUERY_COMPLETE
          if (start_h = @nus_start_handle) && (end_h = @nus_end_handle)
            discover_characteristics_for_service(@conn_handle, start_h, end_h)
            @uart_central_state = :TC_W4_CHAR_RESULT
          else
            debug_puts "NUS service not found, re-scanning"
            _central_reset
            start_scan
            @uart_central_state = :TC_W4_SCAN_RESULT
          end
        end

      when :TC_W4_CHAR_RESULT
        case event_type
        when GATT_EVENT_CHARACTERISTIC_QUERY_RESULT
          value_handle = Utils.little_endian_to_int16(event_packet.byteslice(10, 2))
          uuid_bin = event_packet.byteslice(16, 16)
          if uuid_bin == @rx_uuid_bin
            @peer_rx_handle = value_handle
            debug_puts "RX handle: #{@peer_rx_handle}"
          elsif uuid_bin == @tx_uuid_bin
            @peer_tx_handle = value_handle
            @peer_cccd_handle = value_handle + 1
            debug_puts "TX handle: #{@peer_tx_handle}, CCCD: #{@peer_cccd_handle}"
          elsif @cycle_scan_debug
            debug_puts "GATT characteristic skipped"
            debug_puts "value_handle"
            debug_puts value_handle
          end
        when GATT_EVENT_QUERY_COMPLETE
          if @peer_rx_handle && @peer_tx_handle && (cccd = @peer_cccd_handle)
            if respond_to?(:listen_for_characteristic_value_updates)
              debug_puts "listen_notifications"
              debug_puts listen_for_characteristic_value_updates(@conn_handle, @peer_tx_handle)
            else
              debug_puts "listen_notifications_missing"
            end
            write_characteristic_descriptor_using_descriptor_handle(
              @conn_handle, cccd, "\x01\x00"
            )
            @uart_central_state = :TC_W4_CCCD_WRITE
          else
            debug_puts "NUS characteristics not found, re-scanning"
            _central_reset
            start_scan
            @uart_central_state = :TC_W4_SCAN_RESULT
          end
        end

      when :TC_W4_CCCD_WRITE
        if event_type == GATT_EVENT_QUERY_COMPLETE
          @connected = true
          @uart_central_state = :TC_READY
          debug_puts "NUS central ready"
        end
      end
    end

    def _cycle_handle_command_complete(event_packet)
      _cycle_debug_connect_event(event_packet)
      opcode = Utils.little_endian_to_int16(event_packet.byteslice(3, 2))
      return unless opcode == HCI_OPCODE_HCI_LE_SET_SCAN_ENABLE ||
                    opcode == HCI_OPCODE_HCI_LE_CREATE_CONNECTION
      status = event_packet.getbyte(5) || 0
      if status != 0
        debug_puts "Command complete failed"
        debug_puts "opcode"
        debug_puts opcode
        debug_puts "status"
        debug_puts status
      end
    end

    def _cycle_handle_command_status(event_packet)
      _cycle_debug_connect_event(event_packet)
      opcode = Utils.little_endian_to_int16(event_packet.byteslice(4, 2))
      return unless opcode == HCI_OPCODE_HCI_LE_CREATE_CONNECTION
      status = event_packet.getbyte(2) || 0
      return if status == 0

      debug_puts "Create connection command failed"
      debug_puts "status"
      debug_puts status
      _central_reset
      set_scan_params(:passive, 0x30, 0x30)
      start_scan
      @uart_central_state = :TC_W4_SCAN_RESULT
    end

    def _cycle_handle_connection_complete(event_packet)
      _cycle_debug_connect_event(event_packet)
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

    def _cycle_debug_connect_event(event_packet)
      return unless @cycle_scan_debug
      @cycle_connect_event_count ||= 0
      return if @cycle_connect_event_count >= 12
      @cycle_connect_event_count += 1

      debug_puts "connect_event"
      debug_puts "type"
      debug_puts(event_packet.getbyte(0) || -1)
      debug_puts "subevent"
      debug_puts(event_packet.getbyte(2) || -1)
      debug_puts "len"
      debug_puts event_packet.bytesize
      debug_puts "b3"
      debug_puts(event_packet.getbyte(3) || -1)
      debug_puts "b4"
      debug_puts(event_packet.getbyte(4) || -1)
      debug_puts "b5"
      debug_puts(event_packet.getbyte(5) || -1)
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
          debug_puts "address_type"
          debug_puts adv_report.address_type_code
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

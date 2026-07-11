# Fixed two-slot BLE::UART central for speed and cadence sensors.

require "ble_cycle_packet"
require "ble_cycle_host/advertising_report"
require "ble_cycle_host/notification_event"

module BLECycleHost
  class MultiUARTCentral
    BTSTACK_EVENT_STATE = 0x60
    HCI_STATE_WORKING = 2
    HCI_EVENT_DISCONNECTION_COMPLETE = 0x05
    HCI_EVENT_COMMAND_STATUS = 0x0f
    HCI_EVENT_LE_META = 0x3e
    HCI_EVENT_META_GAP = 0xe7
    HCI_SUBEVENT_LE_CONNECTION_COMPLETE = 0x01
    HCI_SUBEVENT_LE_ADVERTISING_REPORT = 0x02
    HCI_SUBEVENT_LE_ENHANCED_CONNECTION_COMPLETE_V1 = 0x0a
    HCI_SUBEVENT_LE_ENHANCED_CONNECTION_COMPLETE_V2 = 0x29
    GAP_SUBEVENT_LE_CONNECTION_COMPLETE = 0x08
    HCI_OPCODE_HCI_LE_CREATE_CONNECTION = 0x200d
    GATT_EVENT_QUERY_COMPLETE = 0xa0
    GATT_EVENT_SERVICE_QUERY_RESULT = 0xa1
    GATT_EVENT_CHARACTERISTIC_QUERY_RESULT = 0xa2
    GATT_EVENT_NOTIFICATION = 0xa7
    CCCD_NOTIFY = "\x01\x00"

    class Slot
      attr_reader :role
      attr_reader :target_name
      attr_reader :target_address
      attr_reader :reader
      attr_reader :packet
      attr_accessor :state
      attr_accessor :peer_address
      attr_accessor :peer_address_type
      attr_accessor :connection_handle
      attr_accessor :service_start_handle
      attr_accessor :service_end_handle
      attr_accessor :rx_handle
      attr_accessor :tx_handle
      attr_accessor :cccd_handle
      attr_accessor :notification_count
      attr_accessor :target_report_count
      attr_accessor :nonconnectable_report_count
      attr_accessor :service_reject_count

      def initialize(role, target_name, target_address)
        @role = role
        @target_name = target_name
        @target_address = target_address
        @reader = BLECyclePacket::FrameReader.new
        @packet = BLECyclePacket::Decoded.new
        @target_report_count = 0
        @nonconnectable_report_count = 0
        @service_reject_count = 0
        reset
      end

      def ready?
        @state == :ready
      end

      def missing?
        @state == :missing
      end

      def address_configured?
        !@target_address.nil? && !@target_address.empty?
      end

      def reset
        @state = :missing
        @peer_address = nil
        @peer_address_type = nil
        @connection_handle = nil
        @service_start_handle = nil
        @service_end_handle = nil
        @rx_handle = nil
        @tx_handle = nil
        @cccd_handle = nil
        @notification_count = 0
        @reader.clear
        self
      end
    end

    attr_reader :speed_slot
    attr_reader :cadence_slot
    attr_reader :scan_report_count

    def initialize(speed_address:, cadence_address: nil,
                   speed_name: "PRCycle", cadence_name: "PRCad",
                   transport: nil)
      @speed_slot = Slot.new(:speed, speed_name, speed_address)
      @cadence_slot = Slot.new(:cadence, cadence_name, cadence_address)
      @service_uuid_bin = uuid_to_bin(BLECyclePacket::SERVICE_UUID)
      @rx_uuid_bin = uuid_to_bin(BLECyclePacket::RX_UUID)
      @tx_uuid_bin = uuid_to_bin(BLECyclePacket::TX_UUID)
      @notification_event = NotificationEvent.new
      @uart = transport || build_transport
      @uart.event_sink = self if @uart.respond_to?(:event_sink=)
      @debug = false
      @hci_ready = false
      @listener_registered = false
      @scan_active = false
      @scan_report_count = 0
      @pending_slot = nil
      @discovery_slot = nil
      @packet_callback = nil
    end

    def debug=(value)
      @debug = value
      @uart.debug = value if @uart.respond_to?(:debug=)
    end

    def on_packet(&block)
      @packet_callback = block
      self
    end

    def start(&block)
      @packet_callback = block
      @uart.start do
        block.call(nil, nil, nil) if block
      end
    ensure
      if @listener_registered && @uart.respond_to?(:stop_listening_for_all_characteristic_value_updates)
        @uart.stop_listening_for_all_characteristic_value_updates
        @listener_registered = false
      end
    end

    def handle_event(event_packet)
      event_type = event_packet.getbyte(0)
      return false if event_type.nil?

      case event_type
      when BTSTACK_EVENT_STATE
        handle_btstack_state(event_packet)
      when HCI_EVENT_DISCONNECTION_COMPLETE
        handle_disconnection(event_packet)
      when HCI_EVENT_COMMAND_STATUS
        handle_command_status(event_packet)
      when AdvertisingReport::GAP_EVENT_ADVERTISING_REPORT
        handle_advertising(event_packet)
      when HCI_EVENT_LE_META
        handle_le_meta(event_packet)
      when HCI_EVENT_META_GAP
        if event_packet.getbyte(2) == GAP_SUBEVENT_LE_CONNECTION_COMPLETE
          handle_connection_complete(event_packet)
        end
      when GATT_EVENT_QUERY_COMPLETE,
           GATT_EVENT_SERVICE_QUERY_RESULT,
           GATT_EVENT_CHARACTERISTIC_QUERY_RESULT
        handle_gatt_event(event_type, event_packet)
      when GATT_EVENT_NOTIFICATION
        handle_notification(event_packet)
      end
      true
    end

    def speed_ready?
      @speed_slot.ready?
    end

    def cadence_ready?
      @cadence_slot.ready?
    end

    def all_ready?
      @speed_slot.ready? && @cadence_slot.ready?
    end

    def connected?
      @speed_slot.ready? || @cadence_slot.ready?
    end

    def ready_count
      count = @speed_slot.ready? ? 1 : 0
      count += 1 if @cadence_slot.ready?
      count
    end

    def state
      return :off unless @hci_ready
      return :connecting if @pending_slot
      return :discovering if @discovery_slot
      return :scanning if @scan_active
      return :ready if all_ready?
      :idle
    end

    def slot_state(role)
      slot = slot_for_role(role)
      slot ? slot.state : nil
    end

    private

    def build_transport
      require "ble_cycle_host/multi_uart_transport"
      MultiUARTTransport.new(
        role: :central,
        service_uuid: BLECyclePacket::SERVICE_UUID,
        rx_uuid: BLECyclePacket::RX_UUID,
        tx_uuid: BLECyclePacket::TX_UUID
      )
    end

    def handle_btstack_state(event_packet)
      return unless event_packet.getbyte(2) == HCI_STATE_WORKING
      return if @hci_ready

      unless @uart.respond_to?(:listen_for_all_characteristic_value_updates)
        raise "UF2 lacks all-connection BLE notification listener"
      end
      result = @uart.listen_for_all_characteristic_value_updates
      raise "failed to register BLE notification listener: #{result}" unless result == 0

      @listener_registered = true
      @hci_ready = true
      @uart.set_scan_params(:passive, 0x30, 0x30)
      log "multi_central_up"
      resume_scan
    end

    def handle_le_meta(event_packet)
      subevent = event_packet.getbyte(2)
      if subevent == HCI_SUBEVENT_LE_ADVERTISING_REPORT
        handle_advertising(event_packet)
      elsif subevent == HCI_SUBEVENT_LE_CONNECTION_COMPLETE ||
            subevent == HCI_SUBEVENT_LE_ENHANCED_CONNECTION_COMPLETE_V1 ||
            subevent == HCI_SUBEVENT_LE_ENHANCED_CONNECTION_COMPLETE_V2
        handle_connection_complete(event_packet)
      end
    end

    def handle_advertising(event_packet)
      return unless @scan_active
      return if @pending_slot || @discovery_slot

      AdvertisingReport.each(event_packet) do |report|
        @scan_report_count += 1
        log_scan_target_counts if (@scan_report_count % 500) == 0

        slot = identity_matching_missing_slot(report)
        next unless slot
        slot.target_report_count += 1

        unless report.connectable?
          slot.nonconnectable_report_count += 1
          log_rejected_target(slot, report, :nonconnectable)
          next
        end
        unless service_acceptable?(report, slot)
          slot.service_reject_count += 1
          log_rejected_target(slot, report, :service_mismatch)
          next
        end

        connect_slot(slot, report)
        return
      end
    end

    def identity_matching_missing_slot(report)
      if @speed_slot.missing? && identity_matches_slot?(report, @speed_slot)
        return @speed_slot
      end
      if @cadence_slot.missing? && identity_matches_slot?(report, @cadence_slot)
        return @cadence_slot
      end
      nil
    end

    def identity_matches_slot?(report, slot)
      if slot.address_configured?
        report.address_include?(slot.target_address)
      else
        report.name_include?(slot.target_name)
      end
    end

    def service_acceptable?(report, slot)
      # A fixed address is the pairing identity. GATT discovery validates the
      # custom service after connection, even if this advertisement is sparse.
      return true if slot.address_configured?

      service_data = report.reports[:complete_list_128_bit_service_class_uuids] ||
                     report.reports[:incomplete_list_128_bit_service_class_uuids]
      service_data.nil? || service_data.include?(@service_uuid_bin)
    end

    def log_scan_target_counts
      return unless @debug
      log "scan_target_counts"
      log "speed", @speed_slot.target_report_count
      log "cadence", @cadence_slot.target_report_count
    end

    def log_rejected_target(slot, report, reason)
      count = if reason == :nonconnectable
                slot.nonconnectable_report_count
              else
                slot.service_reject_count
              end
      return if count > 3

      log "target_report_rejected"
      log "role", slot.role
      log "reason", reason
      log "addr", report.address_string
      log "event_type", report.event_type
      log "data_len", report.data_length
    end

    def connect_slot(slot, report)
      stop_scan
      slot.state = :connecting
      slot.peer_address = report.address
      slot.peer_address_type = report.address_type_code
      @pending_slot = slot
      log "connecting_role", slot.role
      result = @uart.gap_connect(report.address, report.address_type_code)
      return if result == 0

      log "gap_connect_failed", result
      @pending_slot = nil
      slot.reset
      resume_scan
    end

    def handle_command_status(event_packet)
      return unless @pending_slot
      return unless get_u16(event_packet, 4) == HCI_OPCODE_HCI_LE_CREATE_CONNECTION
      status = event_packet.getbyte(2) || 0
      return if status == 0

      log "connect_command_failed", status
      @pending_slot.reset
      @pending_slot = nil
      resume_scan
    end

    def handle_connection_complete(event_packet)
      slot = @pending_slot
      return unless slot

      status = event_packet.getbyte(3) || 0xff
      if status != 0
        log "connection_failed", status
        slot.reset
        @pending_slot = nil
        resume_scan
        return
      end

      slot.connection_handle = get_u16(event_packet, 4)
      slot.state = :discovering_service
      @pending_slot = nil
      @discovery_slot = slot
      log "connected_role", slot.role
      log "connection_handle", slot.connection_handle
      result = @uart.discover_primary_services(slot.connection_handle)
      discovery_failed(slot, result) unless result == 0
    end

    def handle_gatt_event(event_type, event_packet)
      slot = @discovery_slot
      return unless slot
      return unless get_u16(event_packet, 2) == slot.connection_handle

      case slot.state
      when :discovering_service
        handle_service_event(slot, event_type, event_packet)
      when :discovering_characteristics
        handle_characteristic_event(slot, event_type, event_packet)
      when :subscribing
        finish_subscription(slot, event_type, event_packet)
      end
    end

    def handle_service_event(slot, event_type, event_packet)
      if event_type == GATT_EVENT_SERVICE_QUERY_RESULT
        if event_packet.byteslice(12, 16) == @service_uuid_bin
          slot.service_start_handle = get_u16(event_packet, 8)
          slot.service_end_handle = get_u16(event_packet, 10)
        end
        return
      end
      return unless event_type == GATT_EVENT_QUERY_COMPLETE
      return discovery_failed(slot, query_status(event_packet)) unless query_status(event_packet) == 0
      unless slot.service_start_handle && slot.service_end_handle
        return discovery_failed(slot, :service_not_found)
      end

      result = @uart.discover_characteristics_for_service(
        slot.connection_handle,
        slot.service_start_handle,
        slot.service_end_handle
      )
      if result == 0
        slot.state = :discovering_characteristics
      else
        discovery_failed(slot, result)
      end
    end

    def handle_characteristic_event(slot, event_type, event_packet)
      if event_type == GATT_EVENT_CHARACTERISTIC_QUERY_RESULT
        value_handle = get_u16(event_packet, 10)
        uuid = event_packet.byteslice(16, 16)
        if uuid == @rx_uuid_bin
          slot.rx_handle = value_handle
        elsif uuid == @tx_uuid_bin
          slot.tx_handle = value_handle
          slot.cccd_handle = value_handle + 1
        end
        return
      end
      return unless event_type == GATT_EVENT_QUERY_COMPLETE
      return discovery_failed(slot, query_status(event_packet)) unless query_status(event_packet) == 0
      unless slot.rx_handle && slot.tx_handle && slot.cccd_handle
        return discovery_failed(slot, :characteristic_not_found)
      end

      result = @uart.write_characteristic_descriptor_using_descriptor_handle(
        slot.connection_handle,
        slot.cccd_handle,
        CCCD_NOTIFY
      )
      if result == 0
        slot.state = :subscribing
      else
        discovery_failed(slot, result)
      end
    end

    def finish_subscription(slot, event_type, event_packet)
      return unless event_type == GATT_EVENT_QUERY_COMPLETE
      return discovery_failed(slot, query_status(event_packet)) unless query_status(event_packet) == 0

      slot.state = :ready
      @discovery_slot = nil
      log "ready_role", slot.role
      resume_scan
    end

    def discovery_failed(slot, reason)
      slot.state = :failed
      @discovery_slot = nil if @discovery_slot == slot
      log "discovery_failed_role", slot.role
      log "discovery_error", reason
      resume_scan
    end

    def handle_notification(event_packet)
      return unless @notification_event.parse(event_packet)
      slot = slot_for_connection(@notification_event.connection_handle)
      return unless slot && slot.ready?
      return unless slot.tx_handle == @notification_event.value_handle

      value = @notification_event.value
      return unless value
      slot.reader.push(value)
      slot.notification_count += 1
      while slot.reader.read(slot.packet)
        @packet_callback.call(slot.role, slot.packet, slot.reader) if @packet_callback
      end
    end

    def handle_disconnection(event_packet)
      connection_handle = get_u16(event_packet, 3)
      slot = slot_for_connection(connection_handle)
      return unless slot

      log "disconnected_role", slot.role
      @pending_slot = nil if @pending_slot == slot
      @discovery_slot = nil if @discovery_slot == slot
      slot.reset
      resume_scan
    end

    def resume_scan
      return unless @hci_ready
      return if @scan_active || @pending_slot || @discovery_slot
      return unless @speed_slot.missing? || @cadence_slot.missing?

      @uart.start_scan
      @scan_active = true
      log "scan_started"
    end

    def stop_scan
      return unless @scan_active
      @uart.stop_scan
      @scan_active = false
    end

    def slot_for_connection(connection_handle)
      return @speed_slot if @speed_slot.connection_handle == connection_handle
      return @cadence_slot if @cadence_slot.connection_handle == connection_handle
      nil
    end

    def slot_for_role(role)
      return @speed_slot if role == :speed
      return @cadence_slot if role == :cadence
      nil
    end

    def query_status(event_packet)
      event_packet.getbyte(8) || 0xff
    end

    def get_u16(packet, offset)
      (packet.getbyte(offset) || 0) | ((packet.getbyte(offset + 1) || 0) << 8)
    end

    def uuid_to_bin(uuid)
      hex = uuid.delete("-")
      out = String.new
      i = hex.length - 2
      while 0 <= i
        out << hex.byteslice(i, 2).to_i(16)
        i -= 2
      end
      out
    end

    def log(label, value = nil)
      return unless @debug
      puts label
      puts value unless value.nil?
    end
  end
end

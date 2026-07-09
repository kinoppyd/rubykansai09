# Advertising report parser used by the BLE cycle host bring-up tools.
#
# PicoRuby may deliver scan results either as BTstack GAP_EVENT_ADVERTISING_REPORT
# or as raw HCI_EVENT_LE_META / LE Advertising Report events.

module BLECycleHost
  class AdvertisingReport
    GAP_EVENT_ADVERTISING_REPORT = 0xda
    HCI_EVENT_LE_META = 0x3e
    HCI_SUBEVENT_LE_ADVERTISING_REPORT = 0x02

    AD_TYPE = {
      0x01 => :flags,
      0x02 => :incomplete_list_16_bit_service_class_uuids,
      0x03 => :complete_list_16_bit_service_class_uuids,
      0x06 => :incomplete_list_128_bit_service_class_uuids,
      0x07 => :complete_list_128_bit_service_class_uuids,
      0x08 => :shortened_local_name,
      0x09 => :complete_local_name,
      0x0a => :tx_power_level,
      0xff => :manufacturer_specific_data
    }

    attr_reader :event_type
    attr_reader :address_type_code
    attr_reader :address
    attr_reader :rssi
    attr_reader :reports
    attr_reader :data_length

    def initialize(event_type, address_type_code, address, rssi, reports, data_length = 0)
      @event_type = event_type
      @address_type_code = address_type_code
      @address = address
      @rssi = rssi
      @reports = reports
      @data_length = data_length
    end

    def self.each(packet)
      event_type = packet.getbyte(0)
      if event_type == GAP_EVENT_ADVERTISING_REPORT
        yield from_gap(packet)
        return true
      end
      return false unless event_type == HCI_EVENT_LE_META
      return false unless packet.getbyte(2) == HCI_SUBEVENT_LE_ADVERTISING_REPORT

      count = packet.getbyte(3) || 0
      offset = 4
      i = 0
      while i < count
        event_type_code = packet.getbyte(offset)
        address_type_code = packet.getbyte(offset + 1) || 0
        break if event_type_code.nil?

        address = reverse_address(packet, offset + 2)
        data_length = packet.getbyte(offset + 8) || 0
        data = packet.byteslice(offset + 9, data_length) || ""
        rssi_byte = packet.getbyte(offset + 9 + data_length)
        rssi = signed_i8(rssi_byte || 0)
        yield new(event_type_code, address_type_code, address, rssi, parse_ad_data(data), data.bytesize)
        offset += 10 + data_length
        i += 1
      end
      true
    end

    def self.from_gap(packet)
      src = ::BLE::AdvertisingReport.new(packet)
      new(src.event_type, src.address_type_code, src.address, src.rssi, src.reports)
    end

    def self.parse_ad_data(data)
      reports = {}
      index = 0
      while index < data.bytesize
        length = data.getbyte(index)
        break if length.nil? || length == 0
        type_num = data.getbyte(index + 1)
        break if type_num.nil?
        value = data.byteslice(index + 2, length - 1)
        break if value.nil?
        reports[AD_TYPE[type_num] || type_num] = value
        index += length + 1
      end
      reports
    end

    def name_include?(name)
      @reports[:shortened_local_name]&.include?(name) ||
        @reports[:complete_local_name]&.include?(name)
    end

    def address_string
      @address.bytes.map { |b| sprintf("%02X", b) }.join(":")
    end

    def address_include?(address)
      return false if address.nil?
      normalize_address(address) == normalize_address(address_string)
    end

    def normalize_address(address)
      address.to_s.upcase
    end

    def self.reverse_address(packet, offset)
      address = String.new
      5.downto(0) do |i|
        address << [packet.getbyte(offset + i) || 0].pack("C")
      end
      address
    end

    def self.signed_i8(value)
      value >= 128 ? value - 256 : value
    end
  end
end

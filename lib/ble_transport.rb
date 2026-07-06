# Usage:
#   require "ble_transport"
#   payload = BLETransport.bytes(11)
#   BLETransport.put_u8(payload, 0, 0x03)
#   BLETransport.put_u32(payload, 1, wheel_revolutions)
#   BLETransport.put_u16(payload, 5, BLECSCService.event_time_ticks(time_ms))
#
# Provides BLE constants and little-endian byte helpers used by
# BLECSCService and transport implementations. Methods mutate existing
# strings where possible to avoid extra allocation on PicoRuby.

module BLETransport
  READ = 2
  WRITE = 8
  NOTIFY = 16
  INDICATE = 32
  DYNAMIC = 256

  GATT_PRIMARY_SERVICE_UUID = 0x2800
  GAP_SERVICE_UUID = 0x1800
  GAP_DEVICE_NAME_UUID = 0x2A00
  GAP_APPEARANCE_UUID = 0x2A01
  CLIENT_CHARACTERISTIC_CONFIGURATION = 0x2902

  CSC_SERVICE_UUID = 0x1816
  CSC_MEASUREMENT_UUID = 0x2A5B
  CSC_FEATURE_UUID = 0x2A5C
  CSC_SENSOR_LOCATION_UUID = 0x2A5D
  CSC_CONTROL_POINT_UUID = 0x2A55

  AD_FLAGS = 1
  AD_COMPLETE_LIST_16_BIT_SERVICE_UUIDS = 3
  AD_COMPLETE_LOCAL_NAME = 9
  AD_SHORTENED_LOCAL_NAME = 8
  AD_APPEARANCE = 0x19
  APP_AD_FLAGS = 6

  APPEARANCE_SPEED = 0x0482
  APPEARANCE_CADENCE = 0x0483
  APPEARANCE_SPEED_AND_CADENCE = 0x0485

  def self.bytes(n)
    s = String.new
    i = 0
    while i < n
      s << 0
      i += 1
    end
    s
  end

  def self.u8(v)
    s = String.new
    s << (v & 255)
    s
  end

  def self.u16_le(v)
    s = bytes(2)
    put_u16(s, 0, v)
    s
  end

  def self.s16_le(v)
    v += 0x10000 if v < 0
    u16_le(v)
  end

  def self.u32_le(v)
    s = bytes(4)
    put_u32(s, 0, v)
    s
  end

  def self.put_u8(s, i, v)
    s.setbyte(i, v & 255)
  end

  def self.put_u16(s, i, v)
    v &= 0xffff
    s.setbyte(i, v & 255)
    s.setbyte(i + 1, (v >> 8) & 255)
  end

  def self.put_u32(s, i, v)
    v &= 0xffffffff
    s.setbyte(i, v & 255)
    s.setbyte(i + 1, (v >> 8) & 255)
    s.setbyte(i + 2, (v >> 16) & 255)
    s.setbyte(i + 3, (v >> 24) & 255)
  end

  def self.get_u16(s, i)
    s.getbyte(i) | (s.getbyte(i + 1) << 8)
  end

  def self.get_u32(s, i)
    s.getbyte(i) |
      (s.getbyte(i + 1) << 8) |
      (s.getbyte(i + 2) << 16) |
      (s.getbyte(i + 3) << 24)
  end

  def self.csc_event_time_ticks(time_ms)
    ((time_ms * 1024) / 1000) & 0xffff
  end
end

# Cycling Computer Sensor Communication Standards

Last reviewed: 2026-06-14

## Scope

This document summarizes the communication standards used between existing cycling computers and external sensors. It is written for a custom sensor project using PicoRuby with RP2040/RP2350-class boards and focuses on what must be implemented to interoperate with common head units.

The practical baseline is:

- Implement Bluetooth Low Energy (BLE) GATT first for new custom sensors.
- Treat ANT+ as important for legacy and high-end cycling computers, but plan for extra hardware, licensing/profile access, and a proprietary network key.
- Use proprietary protocols only after confirming a specific head unit/accessory target.

## Main Standards

| Standard | Where it is used | Sensor role | Cycling computer role | Implementation implication |
| --- | --- | --- | --- | --- |
| BLE GATT | Modern sensors, phones, watches, recent cycling computers | Peripheral, GATT Server | Central, GATT Client/Collector | Advertise standard service UUIDs, expose GATT characteristics, send measurements by notification. |
| ANT+ | Many Garmin/Wahoo/Hammerhead-era cycling accessories, especially power/speed/cadence/HR and trainers | ANT channel master/broadcast device | ANT channel slave/display | Broadcast 8-byte data pages at profile-defined intervals. Requires ANT-capable radio/stack and ANT+ profile details. |
| Proprietary BLE/ANT/private radio | Radar, lights, electronic shifting, tire pressure, some e-bike systems | Varies | Varies | Interoperability is vendor-specific. Use only for a known target. |
| Wired legacy sensors | Older magnet speed/cadence sensors | Reed/Hall pulse source | Head unit counts pulses | Not a radio standard. Easy electrically, but not compatible with wireless head units without protocol translation. |

## BLE GATT Architecture

BLE cycling sensors are normally peripherals and GATT servers. The cycling computer scans advertisements, connects as a central, discovers services, enables notifications by writing the Client Characteristic Configuration Descriptor (CCCD), and receives measurement notifications.

Implementation rules that apply across the cycling BLE services:

- Advertise as a connectable peripheral and include the relevant 16-bit service UUID in advertising or scan response data.
- Expose each requested service as a Primary Service.
- Use little-endian byte order for multi-byte fields in the cycling services.
- Send time-sensitive measurements with `Notify`, not `Read`.
- Include a CCCD for every notifiable or indicatable characteristic.
- Add Battery Service (`0x180F`) and Device Information Service (`0x180A`) for better compatibility even when not strictly required.
- Control points use `Write` from the cycling computer and `Indicate` from the sensor for responses.

## BLE Cycling Speed and Cadence Service

Use this when emulating a wheel speed sensor, cadence sensor, or combined speed/cadence sensor.

| Item | Value |
| --- | --- |
| Profile | Cycling Speed and Cadence Profile (CSCP) |
| Service | Cycling Speed and Cadence Service (CSCS), UUID `0x1816` |
| Measurement characteristic | CSC Measurement, UUID `0x2A5B`, `Notify`, mandatory |
| Feature characteristic | CSC Feature, UUID `0x2A5C`, `Read`, mandatory |
| Sensor location | Sensor Location, UUID `0x2A5D`, `Read`, conditional |
| Control point | SC Control Point, UUID `0x2A55`, `Write` + `Indicate`, conditional |

### CSC Measurement Payload

The CSC Measurement value starts with a one-octet Flags field:

| Flag bit | Meaning |
| --- | --- |
| Bit 0 | Wheel Revolution Data Present |
| Bit 1 | Crank Revolution Data Present |
| Bits 2-7 | RFU, transmit as zero |

If wheel data is present, append:

| Field | Type | Unit/meaning |
| --- | --- | --- |
| Cumulative Wheel Revolutions | `uint32` | Total detected wheel revolutions. BLE CSCS expects this not to roll over. |
| Last Wheel Event Time | `uint16` | Free-running time of the latest wheel event in 1/1024 second units; rolls over every 64 seconds. |

If crank data is present, append:

| Field | Type | Unit/meaning |
| --- | --- | --- |
| Cumulative Crank Revolutions | `uint16` | Total detected crank revolutions; may roll over. |
| Last Crank Event Time | `uint16` | Free-running time of the latest crank event in 1/1024 second units; rolls over every 64 seconds. |

Field order is Flags, wheel pair if present, then crank pair if present.

The cycling computer calculates speed, distance, and cadence from deltas between consecutive notifications. The wheel circumference is configured or known on the cycling computer, not transmitted by CSCS.

Typical notification interval is approximately once per second. The interval is chosen by the sensor.

### CSC Feature

`CSC Feature` is a `uint16` bit field:

| Bit | Meaning |
| --- | --- |
| 0 | Wheel Revolution Data Supported |
| 1 | Crank Revolution Data Supported |
| 2 | Multiple Sensor Locations Supported |
| 3-15 | RFU, transmit as zero |

### SC Control Point

Implement this if the sensor supports wheel revolution data or multiple sensor locations. Useful procedures include:

- Set cumulative wheel revolution value.
- Update sensor location.
- Request supported sensor locations.

For a minimal custom sensor, implement it if your BLE stack can support indications cleanly. Some cycling computers still work without it, but omitting it reduces conformance.

## BLE Cycling Power Service

Use this when emulating a power meter.

| Item | Value |
| --- | --- |
| Profile | Cycling Power Profile (CPP) |
| Service | Cycling Power Service (CPS), UUID `0x1818` |
| Feature characteristic | Cycling Power Feature, UUID `0x2A65`, `Read`, mandatory |
| Measurement characteristic | Cycling Power Measurement, UUID `0x2A63`, `Notify`, mandatory |
| Sensor location | Sensor Location, UUID `0x2A5D`, `Read`, mandatory |
| Control point | Cycling Power Control Point, UUID `0x2A66`, `Write` + `Indicate`, optional |
| Vector | Cycling Power Vector, UUID `0x2A64`, `Notify`, optional |

### Cycling Power Measurement Payload

The measurement begins with:

| Field | Type | Unit/meaning |
| --- | --- | --- |
| Flags | `uint16` | Presence bits and status bits for optional fields. |
| Instantaneous Power | `sint16` | Watts. Mandatory. |

Optional fields selected by Flags include:

| Optional field | Purpose |
| --- | --- |
| Pedal Power Balance | Left/right contribution estimate. |
| Accumulated Torque | Total torque integration. |
| Wheel Revolution Data | Wheel revolutions plus event time, for speed/distance support. |
| Crank Revolution Data | Crank revolutions plus event time, for cadence support. |
| Extreme Force Magnitudes | Min/max force in a measurement window. |
| Extreme Torque Magnitudes | Min/max torque in a measurement window. |
| Extreme Angles | Crank angles where force/torque extrema occurred. |
| Top/Bottom Dead Spot Angles | Pedaling phase landmarks. |
| Accumulated Energy | Energy in kilojoules since connection; starts at zero and is not expected to roll over. |

A minimal interoperable BLE power meter can expose only Flags and Instantaneous Power, but real cycling computers behave better when cadence is also present through the Crank Revolution Data field pair or through a separate CSCS cadence sensor.

### Cycling Power Control Point

Control point support is optional but expected on higher-quality power meters. Procedures include setting the cumulative wheel value, updating sensor location, setting mechanical parameters, starting offset compensation/zero calibration, masking measurement content, requesting sampling rate, and requesting factory calibration date.

### Cycling Power Vector

Vector data is optional and intended for high-rate force/torque arrays across a crank revolution. Skip it unless building an advanced power meter.

## BLE Heart Rate Service

Use this when emulating a heart-rate strap or optical heart-rate sensor that a cycling computer can pair with.

| Item | Value |
| --- | --- |
| Profile | Heart Rate Profile (HRP) |
| Service | Heart Rate Service (HRS), UUID `0x180D` |
| Measurement characteristic | Heart Rate Measurement, UUID `0x2A37`, `Notify`, mandatory |
| Body sensor location | Body Sensor Location, UUID `0x2A38`, `Read`, optional |
| Control point | Heart Rate Control Point, UUID `0x2A39`, `Write`, conditional if Energy Expended is supported |

The Heart Rate Measurement starts with a one-octet Flags field, followed by the heart-rate value and optional fields:

| Field | Type | Unit/meaning |
| --- | --- | --- |
| Heart Rate Measurement Value | `uint8` or `uint16` | bpm. Use `uint8` for values <= 255 bpm. |
| Sensor Contact Status | Flags bits | Whether skin contact is supported and detected. |
| Energy Expended | `uint16` | Kilojoules since last reset. |
| RR-Interval | one or more `uint16` values | Time between heart beats in 1/1024 second units. |

Typical notification rate is approximately once per second.

## BLE Fitness Machine Service

Use this only if building an indoor trainer or controllable resistance device. For a normal on-bike sensor, CSCS/CPS/HRS are the relevant services.

| Item | Value |
| --- | --- |
| Service | Fitness Machine Service (FTMS), UUID `0x1826` |
| Feature | Fitness Machine Feature, UUID `0x2ACC`, `Read` |
| Indoor bike data | Indoor Bike Data, UUID `0x2AD2`, `Notify` |
| Control point | Fitness Machine Control Point, UUID `0x2AD9`, `Write` + `Indicate` |
| Status | Fitness Machine Status, UUID `0x2ADA`, `Notify` |

Indoor bike data can include speed, cadence, power, resistance, distance, energy, and heart rate depending on feature flags. Control point commands are used for target power, resistance, simulation parameters, and session control.

## ANT+ Architecture

ANT+ is a profile layer on top of ANT. In common cycling use, the sensor is the channel master and the cycling computer is the display/receiver. The sensor repeatedly broadcasts profile-defined 8-byte data pages; the cycling computer pairs by device number/type/transmission type and decodes pages for that profile.

Implementation implications:

- RP2040/RP2350 boards do not include an ANT radio. Use an external ANT module/SoC or a radio with a licensed ANT stack.
- ANT+ uses the reserved ANT+ network key and 2457 MHz frequency. The public ANT page notes that the ANT+ membership and product certification programs ended on 2025-06-30, but the installed device ecosystem still exists.
- The base ANT payload is fixed at 8 bytes. Additional identity, product, and battery data are sent as separate common/profile pages over time.
- Most ANT+ cycling sensors are broadcast one-to-many. Several head units can receive the same sensor.
- Exact byte layouts are profile-specific. Use the official profile PDF for any production-compatible implementation.

## ANT+ Cycling Profiles and Data

| ANT+ profile | Use | Main sensor-to-computer data |
| --- | --- | --- |
| Bicycle Speed | Wheel speed sensor | Latest speed event time, cumulative wheel revolutions, optional stopped flag, battery, operating time, manufacturer/product identity. |
| Bicycle Cadence | Crank cadence sensor | Latest cadence event time, cumulative pedal revolutions, optional stopped flag, battery, operating time, manufacturer/product identity. |
| Combined Bicycle Speed and Cadence | One sensor for both wheel and crank | Speed and cadence event times and cumulative revolution counts on one ANT channel. |
| Bicycle Power | Power meter | Instantaneous power, accumulated power, pedal balance, cadence, torque variants, calibration, manufacturer/product identity, battery. |
| Heart Rate Monitor | HR strap/optical HR | Last heart beat, previous heart beat time, beat count, computed heart rate, identity, operating time, battery, optional swim/advanced pages. |
| Fitness Equipment / FE-C | Smart trainer | Distance, speed, heart rate, cadence, power, resistance, capabilities, calibration; reverse-direction control for resistance, target power, and simulation parameters. |
| Environment | Temperature sensor | Current temperature, optional 24-hour high/low, optional stored file transfer. |
| Light Electric Vehicle | E-bike/LEV display link | Speed, distance, system state, gear state, battery, range, assist/travel mode, temperatures, errors; reverse-direction controls for gear/mode/lights. |
| Suspension / Dropper / Controls | Bike accessory control/status | Accessory-specific status plus reverse-direction commands. Compatibility varies by head unit. |
| Muscle Oxygen Monitor | NIRS muscle oxygen sensor | Total hemoglobin concentration, current and previous saturated hemoglobin percentage, capabilities, session markers. |

## Proprietary and Semi-Proprietary Accessory Classes

Some device categories are visible in real cycling setups but are not as straightforward as CSCS/CPS/HRS:

- Electronic shifting: reports selected gears, battery, and sometimes shift mode. Shimano Di2, SRAM AXS, and Campagnolo ecosystems vary.
- Radar: rear-facing radar devices commonly pair with cycling computers, but implementations are vendor/profile-specific. Confirm the exact target before attempting compatibility.
- Smart lights: may use ANT+ controls, private ANT, private BLE, or vendor apps.
- Tire pressure: some systems expose pressure and battery through private ANT/BLE profiles.
- E-bike systems: may expose BLE, ANT+ LEV, CAN/UART bridges, or vendor protocols.

## Derived Values

Cycling computers derive user-facing metrics from transmitted counters:

| Metric | Formula |
| --- | --- |
| Speed | `(delta wheel revolutions * wheel circumference meters) / delta event time seconds` |
| Distance | `delta wheel revolutions * wheel circumference meters` |
| Cadence | `(delta crank revolutions / delta event time seconds) * 60` |
| Power from torque | `torque_Nm * angular_velocity_rad_per_second` |
| Energy | Integral of power over time; BLE CPS may also transmit accumulated energy in kJ. |

For event time counters that roll over, compute deltas modulo `65536` ticks. With 1/1024 second units, `65536 / 1024 = 64` seconds.

## Minimal Implementation Targets

For a custom on-bike sensor:

1. BLE CSCS speed/cadence sensor.
2. BLE CPS power meter if measuring or estimating watts.
3. BLE HRS only if the device is body-worn or receiving HR from another module.
4. Battery Service and Device Information Service.
5. ANT+ only if the target cycling computer requires it and the hardware/legal path is clear.
6. FTMS only for a smart trainer/resistance unit.

## RP2040/RP2350 Notes

Plain RP2040/RP2350 boards do not include BLE or ANT radios. A Pico W-class board includes a BLE-capable radio, but firmware and PicoRuby support must be confirmed. For a clean architecture, keep the sensor logic separate from the radio transport:

- Sensor layer: wheel/crank events, torque samples, heart-rate samples, battery state.
- Protocol layer: BLE GATT service encoder or ANT+ data-page encoder.
- Radio layer: BLE stack, ANT module command API, or vendor SDK bridge.

## Sources

- Bluetooth SIG, [Cycling Speed and Cadence Service 1.0](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/CSCS_v1.0/out/en/index-en.html)
- Bluetooth SIG, [Cycling Speed and Cadence Profile 1.0](https://www.bluetooth.com/specifications/specs/cycling-speed-and-cadence-profile-1-0/)
- Bluetooth SIG, [Cycling Power Service 1.1](https://www.bluetooth.com/specifications/specs/cycling-power-service-1-1/)
- Bluetooth SIG, [Cycling Power Profile 1.1](https://www.bluetooth.com/specifications/specs/cycling-power-profile-1-1/)
- Bluetooth SIG, [Heart Rate Service 1.0](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/HRS_v1.0/out/en/index-en.html)
- Bluetooth SIG, [Fitness Machine Service 1.0](https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0/)
- Bluetooth SIG, [Supplement to the Bluetooth Core Specification, Data Types](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/CSS_v12/out/en/supplement-to-the-bluetooth-core-specification/data-types-specification.html)
- Garmin Canada / THIS IS ANT, [ANT Basics](https://www.thisisant.com/developer/ant/ant-basics/)
- Garmin Canada / THIS IS ANT, [ANT+ Device Profiles](https://www.thisisant.com/developer/ant-plus/device-profiles/)

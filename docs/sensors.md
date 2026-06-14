# Cycling Sensor Output Reference

Last reviewed: 2026-06-14

## Purpose

This document describes what data a custom sensor must output to reproduce the behavior of common cycling sensors. It complements `docs/spec.md`, which focuses on communication standards.

The key pattern is that cycling computers often do not receive final values such as "speed" or "cadence" from simple sensors. They receive cumulative event counters and timestamps, then calculate speed, distance, and cadence themselves.

## Recommended Rebuild Order

| Priority | Sensor | Why |
| --- | --- | --- |
| 1 | BLE speed/cadence | Easiest useful target; only revolution counters and event times are required. |
| 2 | BLE power | Most cycling computers support it; minimum payload is small. |
| 3 | Battery/device information | Improves pairing UX and compatibility. |
| 4 | ANT+ speed/cadence/power | Important for existing bike computers, but needs ANT hardware/stack/profile access. |
| 5 | Smart trainer / FTMS / FE-C | Only needed for indoor resistance control. |
| 6 | Accessory profiles | Lights, radar, shifting, tire pressure, e-bike data; target-specific. |

## Speed Sensor

### Physical Inputs

- Wheel revolution events from a reed switch, Hall sensor, magnetometer, optical interrupter, or IMU-based detector.
- Wheel circumference is normally configured on the cycling computer, not sent by the sensor.

### BLE Output

Use Cycling Speed and Cadence Service (`0x1816`) with CSC Measurement (`0x2A5B`).

For speed-only notifications:

| Field | Required value |
| --- | --- |
| Flags | Bit 0 set, bit 1 clear (`0x01`) |
| Cumulative Wheel Revolutions | `uint32`, increment once per valid wheel revolution |
| Last Wheel Event Time | `uint16`, event timestamp in 1/1024 second ticks |

### ANT+ Output

Use the Bicycle Speed profile. The public ANT+ profile summary lists latest speed event time and cumulative wheel revolutions as the core data, with optional stopped flag, battery, operating time, and product identity.

### Reproduction Notes

- Debounce the revolution sensor. A false extra pulse directly becomes false distance.
- For BLE CSCS, cumulative wheel revolutions are not expected to roll over.
- Event time rolls over every 64 seconds; the cycling computer handles modulo deltas.
- If the bicycle stops, keep notifying periodically with unchanged revolution count and unchanged last event time. The computer derives zero speed from no new events.
- If reverse rolling is supported, do not decrement below zero for BLE CSCS.

## Cadence Sensor

### Physical Inputs

- Crank revolution events from a magnet/Hall pair, reed switch, accelerometer, or IMU.

### BLE Output

Use CSCS with CSC Measurement.

For cadence-only notifications:

| Field | Required value |
| --- | --- |
| Flags | Bit 0 clear, bit 1 set (`0x02`) |
| Cumulative Crank Revolutions | `uint16`, increment once per valid crank revolution |
| Last Crank Event Time | `uint16`, event timestamp in 1/1024 second ticks |

### ANT+ Output

Use the Bicycle Cadence profile. The public ANT+ profile summary lists latest cadence event time and cumulative pedal revolutions as the core data, with optional stopped flag, battery, operating time, and product identity.

### Reproduction Notes

- Avoid counting crank movements that happen while coasting if the detector can be fooled by magnet position or vibration.
- `uint16` crank revolution counters may roll over; clients calculate modulo deltas.
- Cadence is computed by the cycling computer from delta crank revolutions and delta time.

## Combined Speed and Cadence Sensor

### BLE Output

Use one CSCS service and set both Flags bits:

| Field | Required value |
| --- | --- |
| Flags | Bits 0 and 1 set (`0x03`) |
| Wheel data | Cumulative Wheel Revolutions + Last Wheel Event Time |
| Crank data | Cumulative Crank Revolutions + Last Crank Event Time |

Field order is Flags, wheel data pair, crank data pair.

### ANT+ Output

Use the Combined Bicycle Speed and Cadence profile. ANT+ also permits separate speed and cadence sensors on two channels; displays are encouraged by ANT+ to support speed-only, cadence-only, two-sensor, and combined-sensor modes.

### Reproduction Notes

- A combined sensor should keep independent wheel and crank event timers.
- It is acceptable for one pair to be unchanged while the other changes, for example coasting downhill.

## Power Meter

### Physical Inputs

Power meters usually combine:

- Torque or force measurement from strain gauges, pedal spindles, crank arms, spider, bottom bracket, chainring, or hub.
- Angular velocity from crank or hub rotation.
- Temperature for offset/strain compensation.

Mechanical power is:

```text
power_watts = torque_newton_meters * angular_velocity_radians_per_second
```

### BLE Output

Use Cycling Power Service (`0x1818`) with Cycling Power Measurement (`0x2A63`).

Minimal interoperable payload:

| Field | Required value |
| --- | --- |
| Flags | `uint16`; zero if no optional fields are present |
| Instantaneous Power | `sint16`, watts |

Recommended optional fields:

| Optional output | Why it helps |
| --- | --- |
| Crank Revolution Data | Lets the head unit show cadence from the power meter. |
| Accumulated Energy | Lets the head unit cross-check energy/kJ. |
| Pedal Power Balance | Useful for dual-sided or estimated left/right devices. |
| Accumulated Torque | Useful for richer analysis and some head-unit pages. |
| Wheel Revolution Data | Useful for hub-based systems that can also provide speed. |

### ANT+ Output

Use the Bicycle Power profile. Existing cycling computers commonly expect instantaneous power and accumulated power/event data, with optional pages for cadence, pedal balance, torque variants, calibration, manufacturer/product identity, and battery.

### Reproduction Notes

- Always send plausible, bounded power values. `sint16` permits negative values, but normal cycling computers expect mostly non-negative ride data.
- If cadence is included, use real crank event timestamps rather than deriving cadence only from sampled rpm.
- Support zero-offset/calibration procedures if the head unit will expose a "calibrate power meter" workflow.
- Temperature compensation matters if using strain gauges.
- For a pure emulator, instantaneous power plus crank revolution data is the smallest useful target.

## Heart Rate Sensor

### Physical Inputs

- Electrical heart beat detection from a chest strap, or optical pulse estimate from PPG.

### BLE Output

Use Heart Rate Service (`0x180D`) with Heart Rate Measurement (`0x2A37`).

Minimal payload:

| Field | Required value |
| --- | --- |
| Flags | `0x00` for `uint8` bpm with no optional fields |
| Heart Rate Measurement Value | bpm as `uint8` for <= 255 bpm |

Useful optional fields:

| Optional output | Meaning |
| --- | --- |
| Sensor Contact Status | Whether skin contact is supported and currently detected. |
| RR-Interval | One or more beat-to-beat intervals in 1/1024 second units. |
| Energy Expended | Kilojoules since reset, if calculated. |
| Body Sensor Location | Chest, wrist, finger, etc. |

### ANT+ Output

Use the Heart Rate Monitor profile. The public ANT+ profile summary lists last heart beat, previous heart beat time, beat count, and computed heart rate as core data, with optional identity, operating time, capabilities, battery, and swim interval summary.

### Reproduction Notes

- Notify around once per second.
- If RR intervals are provided, include all intervals that fit in the ATT MTU and carry the rest into the next notification.
- If contact is poor, set the contact bits rather than sending impossible bpm values.

## Smart Trainer / Indoor Bike

### Physical Inputs and Outputs

Smart trainers may measure:

- Rear-wheel or flywheel speed.
- Crank cadence.
- Torque/power.
- Resistance level.
- Simulated grade or target wattage state.

They may also control:

- Brake/resistance percentage.
- Target power in erg mode.
- Simulation parameters such as grade, wind, rolling resistance, and rider mass.

### BLE Output

Use Fitness Machine Service (`0x1826`) for a controllable trainer:

| Characteristic | Purpose |
| --- | --- |
| Fitness Machine Feature (`0x2ACC`) | Advertises supported data and controls. |
| Indoor Bike Data (`0x2AD2`) | Sends speed, cadence, power, resistance, distance, energy, and related fields depending on flags. |
| Fitness Machine Control Point (`0x2AD9`) | Receives control commands and returns indications. |
| Fitness Machine Status (`0x2ADA`) | Reports state changes. |

For a non-controllable sensor mounted on a bike, use CSCS and CPS instead of FTMS.

### ANT+ Output

Use Fitness Equipment / FE-C for controllable trainers. ANT+ FE-C broadcasts real-time workout data and accepts resistance control, target power, simulation parameters, user configuration, and calibration information.

## Environment Sensor

### Physical Inputs

- Temperature sensor, and optionally pressure/humidity depending on the target profile.

### Outputs

| Protocol | Output |
| --- | --- |
| ANT+ Environment | Current temperature, optional 24-hour low/high, optional file transfer. |
| BLE Environmental Sensing Service | Temperature characteristic and optional environmental characteristics, if the target cycling computer supports them. |

### Reproduction Notes

- ANT+ environment sensors commonly transmit temperature at either low rate or higher requested rate.
- Many cycling computers already have internal temperature sensors, so external support varies.

## E-Bike / Light Electric Vehicle Sensor

### Physical Inputs

- Wheel speed.
- Battery state of charge and voltage.
- Assist mode, travel mode, gear state.
- Motor/battery temperature.
- Range estimate and error state.

### Outputs

ANT+ LEV-style data can include speed, distance, system/gear state, current travel mode, battery, remaining range, distance since last charge, fuel/energy use, temperatures, assistance percentage, wheel circumference, and errors. Some systems accept reverse-direction commands for gear, travel mode, lights, and indicators.

### Reproduction Notes

- Compatibility is highly head-unit-specific.
- If the goal is simply to display speed/cadence/power on a cycling computer, CSCS/CPS are easier than LEV.

## Electronic Shifting / Gear Sensor

### Physical Inputs

- Front and rear derailleur position.
- Gear tooth counts or configured gear table.
- Shift mode and battery state.

### Outputs

Typical head-unit display data:

- Front gear index.
- Rear gear index.
- Gear ratio or tooth counts.
- Battery level.
- Shift mode.

### Reproduction Notes

Shimano Di2, SRAM AXS, and other shifting systems vary by vendor and generation. Do not assume a generic BLE service will be accepted by a cycling computer.

## Lights, Radar, Tire Pressure, Suspension, Dropper

These accessories exist in real cycling computer ecosystems, but they are less suitable as first targets:

| Accessory | Data to reproduce | Notes |
| --- | --- | --- |
| Smart lights | Light mode, battery, on/off/beam commands | Often ANT+ Controls or vendor private BLE/ANT. |
| Rear radar | Relative target distance/speed, threat level, battery | Usually tied to vendor-specific profiles. |
| Tire pressure | Pressure, temperature, leak status, battery | Often private ANT/BLE even when head units support display. |
| Suspension | Lock state, damping mode, auto/manual summaries, battery | ANT+ has a profile summary, but head-unit support varies. |
| Dropper seatpost | Lock/unlock status, battery, commands | ANT+ profile exists; practical compatibility is limited. |

## Minimal BLE Payload Examples

### CSCS Speed-Only

```text
flags:                          uint8   0x01
cumulative_wheel_revolutions:   uint32  little endian
last_wheel_event_time:          uint16  little endian, 1/1024 s ticks
```

### CSCS Cadence-Only

```text
flags:                          uint8   0x02
cumulative_crank_revolutions:   uint16  little endian
last_crank_event_time:          uint16  little endian, 1/1024 s ticks
```

### CSCS Combined

```text
flags:                          uint8   0x03
cumulative_wheel_revolutions:   uint32  little endian
last_wheel_event_time:          uint16  little endian, 1/1024 s ticks
cumulative_crank_revolutions:   uint16  little endian
last_crank_event_time:          uint16  little endian, 1/1024 s ticks
```

### CPS Minimal Power

```text
flags:                          uint16  0x0000, little endian
instantaneous_power:            sint16  watts, little endian
```

### HRS Minimal Heart Rate

```text
flags:                          uint8   0x00
heart_rate_bpm:                 uint8
```

## Sources

- Bluetooth SIG, [Cycling Speed and Cadence Service 1.0](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/CSCS_v1.0/out/en/index-en.html)
- Bluetooth SIG, [Cycling Power Service 1.1](https://www.bluetooth.com/specifications/specs/cycling-power-service-1-1/)
- Bluetooth SIG, [Heart Rate Service 1.0](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/HRS_v1.0/out/en/index-en.html)
- Bluetooth SIG, [Fitness Machine Service 1.0](https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0/)
- Garmin Canada / THIS IS ANT, [ANT Basics](https://www.thisisant.com/developer/ant/ant-basics/)
- Garmin Canada / THIS IS ANT, [ANT+ Device Profiles](https://www.thisisant.com/developer/ant-plus/device-profiles/)

# PicoRuby BLE Sensor Module TODO

最終更新: 2026-06-14 22:28:44 JST

## 残タスク

### 実機 BLE 検証

- [ ] Pico W / Pico 2 W 実機で `BLETransport::PicoRubyPeripheral` が起動するか確認する。
- [ ] BLE scanner で advertisement を確認する。
  - [ ] device name
  - [ ] service UUID `0x1816`
  - [ ] connectable advertising
- [ ] GATT discovery を確認する。
  - [ ] CSCS
  - [ ] CSC Measurement
  - [ ] CSC Feature
  - [ ] CCCD
  - [ ] Battery Service
  - [ ] Device Information Service
- [ ] nRF Connect で CSC Measurement notification を subscribe して値を確認する。
- [ ] 実サイコンで pairing できるか確認する。
- [ ] Wheel circumference をサイコン側に設定し、速度と距離が期待通りか確認する。
- [ ] クランク回転を止めた時に cadence が 0 へ落ちるか確認する。
- [ ] 停止中の periodic notification でサイコン表示が不安定にならないか確認する。
- [ ] 電源断/再起動/再接続時の counter behavior を確認する。
- [ ] サイコンは SC Control Point なしの CSCS sensor を許容するか確認する。

### PicoRuby Firmware / Build

- [ ] `picoruby-ble`, `picoruby-cyw43`, `picoruby-i2c` を含む PicoRuby firmware build 設定を作る。
- [ ] PicoRuby firmware に BLE support を入れた場合の binary size と RAM 使用量を確認する。
- [ ] Pico W/Pico 2 W の BLE と I2C sampling を同時実行した時、sampling jitter が許容範囲か確認する。
- [ ] `BLETransport::PicoRubyPeripheral#start { sensor.tick }` の実機 event loop 周期を調整する。

### Hardware Calibration

- [ ] 対象 board を最終決定する。
  - [ ] Pico W / Pico WH
  - [ ] Pico 2 W
  - [ ] 外部 BLE module
- [ ] Wheel-only / cadence-only / combined のうち、最初に実機で通すべき組み合わせを決める。
- [ ] Mounting orientation を実機で calibration する UI が必要か決める。
- [ ] wheel axis / crank axis の実機推奨値を決める。
- [ ] wheel direction / crank direction の実機推奨値を決める。
- [ ] false positive を抑える初期設定を実走またはローラーで調整する。
  - [ ] `alpha`
  - [ ] `min_period_ms`
  - [ ] `max_period_ms`
  - [ ] `gyro_deadband_dps`

### Battery

- [ ] 電池電圧を測る ADC pin と分圧比を決める。
- [ ] USB 給電時と battery 駆動時の Battery Level 表示方針を決める。
- [ ] Battery Level characteristic `0x2A19` を実 ADC 値で更新する。

### Optional CPS Power Meter

- [ ] power を推定または測定する前提ができたら CPS を追加する。
- [ ] Cycling Power Service UUID `0x1818` を advertise に追加する。
- [ ] Cycling Power Measurement `0x2A63` を `Notify` で追加する。
- [ ] 最小 payload を実装する。
  - [ ] flags `0x0000`
  - [ ] instantaneous power `sint16` watts
- [ ] cadence を CPS 側に含めるか、CSCS cadence として出すか決める。
- [ ] zero-offset/calibration control point が必要か実サイコンで確認する。

### Debug Telemetry

- [ ] 既存サイコン互換とは別に、開発用 custom service を作るか決める。
- [ ] 送る候補を決める。
  - [ ] raw accel
  - [ ] raw gyro
  - [ ] roll/pitch/yaw
  - [ ] wheel/crank phase
  - [ ] detector threshold
  - [ ] false-positive counter
- [ ] debug service は release build で無効化できるようにする。
- [ ] notification rate を上げすぎて CSCS notification を阻害しないようにする。

## Sources

- Raspberry Pi, [Pico microcontroller boards](https://www.raspberrypi.com/documentation/microcontrollers/pico-series.html)
- PicoRuby, [picoruby/picoruby](https://github.com/picoruby/picoruby)
- Bluetooth SIG, [Cycling Speed and Cadence Service 1.0](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/CSCS_v1.0/out/en/index-en.html)
- Project docs, [spec.md](docs/spec.md)
- Project docs, [sensors.md](docs/sensors.md)

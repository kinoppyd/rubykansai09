# PicoRuby BLE Sensor Module TODO

最終更新: 2026-06-28 JST

## 残タスク

### Pico 2 W 2台による BLE Current Time 送受信サンプル

#### 0. 完了条件と用語を固定する

- [ ] 2台の Raspberry Pi Pico 2 W で、以下の役割を分担する。
  - [ ] センサ側: BLE Peripheral / GATT Server。
  - [ ] サイコン側: BLE Central / GATT Client と ST7789 LCD。
- [ ] 本サンプルの「ペアリング」の基本フローを、スキャン、候補一覧、ユーザ選択、接続、GATT discovery、notification subscribe と定義する。
- [ ] BLE Security Manager の Just Works pairing / bonding は、上記の接続フローと分けて検証する。
- [ ] センサの現在時刻は `Time.now` から取得する。RTC 未設定時は値が正しい実時刻ではないことを表示し、実機検証前に R2P2 の時刻を設定する。
- [ ] PicoRuby / R2P2 の対象ファームウェアに `ble`, `cyw43`, `time`, `spi`, `gpio` が入っていることを確認する。

#### 1. 通信仕様と共通コード

- [ ] Bluetooth SIG の Current Time Service を使い、独自の文字列プロトコルは作らない。
  - [ ] Current Time Service UUID: `0x1805`
  - [ ] Current Time characteristic UUID: `0x2A2B`
  - [ ] characteristic properties: `Read | Notify | Dynamic`
  - [ ] CCCD UUID: `0x2902`
- [ ] Current Time characteristic の10 byte payloadを、year、month、day、hour、minute、second、day of week、fractions256、adjust reason の順で encode / decode する小さな共通モジュールを追加する。
- [ ] 起動時間と受信抜けも検証できるよう、LCD 表示用の受信回数と最終受信経過時間をサイコン側で管理する。
- [ ] 固定長 payload、固定上限のデバイス一覧、再利用する表示バッファを使い、PicoRuby 上での一時オブジェクト生成を抑える。
- [ ] 共通モジュールに host Ruby で動く encode / decode テストを追加する。

#### 2. センサ側 Peripheral サンプル

- [ ] `examples/ble_current_time/sensor.rb` を作成する。
- [ ] GAP Device Name を `PicoRuby Time Sensor` とし、connectable advertisement に以下を入れる。
  - [ ] General Discoverable / BR/EDR Not Supported flags。
  - [ ] Complete Local Name。
  - [ ] Complete List of 16-bit Service UUIDs の Current Time Service `0x1805`。
- [ ] GATT database に GAP service、Current Time Service、Current Time characteristic、CCCD を登録する。
- [ ] 1秒ごとに `Time.now` を10 byteに encode し、read value を更新する。
- [ ] Central が CCCD へ `0x0001` を書いた後だけ、1秒ごとに notification を送る。
- [ ] 接続、subscribe、notification 送信、切断の状態を USB serial に最小限出力する。
- [ ] 切断後に状態と CCCD をリセットし、advertisement を再開する。
- [ ] 現行の `BLETransport::PicoRubyPeripheral` と重複する event loop / advertise / disconnect 処理は、メモリ増加が小さい範囲で共通化できるか判断する。

#### 3. サイコン側 Central サンプル

- [ ] `examples/ble_current_time/computer.rb` を作成する。
- [ ] 起動時に一定時間スキャンし、advertisement に Current Time Service `0x1805` を含む connectable device だけを候補にする。
- [ ] BLE address で重複を除き、最大8件まで name、address、RSSI を保持する。
- [ ] スキャン中、0件、スキャン終了、選択待ちの状態を ST7789 LCD と USB serial の両方へ表示する。
- [ ] 検出候補に `1` から始まる番号を付けて LCD に一覧表示し、USB serial の数値プロンプトで選択する。
- [ ] 入力は重い line editor に依存せず、`STDIN` の最小構成で数値、rescan、cancel を扱う。
- [ ] 不正な番号、候補0件、入力キャンセルでクラッシュせず、再スキャンできるようにする。
- [ ] 選択した advertisement report の address / address type で接続する。
- [ ] Current Time Service だけを対象に service / characteristic / CCCD を discovery し、CCCD に `0x0001` を書く。
- [ ] PicoRuby BLE で未実装の `GATT_EVENT_NOTIFICATION` 解析を追加し、connection handle、value handle、value length、payload を安全に取得する。
- [ ] 通知を decode し、センサ名、接続状態、受信時刻、受信回数、最終受信経過時間を `ST7789DebugConsole` へ表示する。
- [ ] 接続 timeout、service 不足、subscribe 失敗、通知 timeout、切断を LCD に表示し、一覧画面へ戻れるようにする。
- [ ] `BLE#start` の終了時に HCI power off される仕様を踏まえ、scan、prompt、connect、subscribe、receive を同じ Central runtime 上の状態機械として実行する。

#### 4. Just Works pairing / bonding

- [ ] 暗号化なしの connect / subscribe / notify で、まず2台間の基本動作を成立させる。
- [ ] `picoruby-ble` が設定している `IO_CAPABILITY_NO_INPUT_NO_OUTPUT` と Just Works の動作を、Peripheral / Central の両方で確認する。
- [ ] Central 側で `SM_EVENT_JUST_WORKS_REQUEST` が処理されない場合は、`picoruby-ble` の RP2040/RP2350 port に confirm 処理と必要な event forwarding を追加する。
- [ ] CCCD への書き込みまたは Current Time characteristic に encryption 要件を設け、接続時に Just Works pairing が実際に発生するテスト構成を用意する。
- [ ] bonding key の保存先を確認し、現行実装が RAM 保持のみなら、再起動後の再ペアリングが必要であることを明記する。
- [ ] セキュリティ pairing を有効にしない基本モードと、Just Works を検証するモードを定数で切り替えられるようにする。

#### 5. テストと実機検証

- [ ] fake advertising report を使い、service UUID filter、address 重複除外、8件上限、RSSI 更新を host Ruby でテストする。
- [ ] 選択番号の正常系、範囲外、空入力、rescan、cancel をテストする。
- [ ] GATT notification packet の最小長、不正長、異なる value handle、正常10 byte payload をテストする。
- [ ] センサ切断後の再 advertise、サイコン切断後の再 scan を状態機械のテストで確認する。
- [ ] Pico 2 W 向け Ruby ファイルを `.mrb` にコンパイルし、R2P2 上での load 時 RAM 使用量を抑える。
- [ ] センサ側のみを起動し、スマートフォンの BLE scanner で name、`0x1805`、GATT database、1秒ごとの notification を確認する。
- [ ] 2台を起動し、サイコン側 LCD の候補一覧からセンサを選択し、接続後に時刻が1秒ごとに更新されることを確認する。
- [ ] 複数の advertiser がある環境でも Current Time Service のみが一覧に残り、選択した address へ接続することを確認する。
- [ ] センサ側の電源断、サイコン側の再起動、通信範囲外からの復帰、bonding 有無の各ケースを確認する。

#### 6. 手順書

- [ ] `docs/ble/current_time_demo.md` と `docs/ble/current_time_demo.ja.md` を作成する。
- [ ] 2台へのファイル配置、R2P2 からの起動方法、LCD 配線と pin 設定、RTC / 時刻設定、実行順序を記載する。
- [ ] スキャン、選択、接続、subscribe、受信の各正常ログと、主なエラー表示を記載する。
- [ ] 本サンプルは Current Time Service の動作確認用であり、実際のサイコン互換センサにする場合は CSCS `0x1816` などへ置き換えることを明記する。

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
- Project docs, [rotation_detector.dm](docs/mpu_6050/rotation_detector.dm)

# PicoRuby Custom BLE Cycle Computer TODO

最終更新: 2026-07-10 JST

> **履歴資料:** 旧CSCS実装と単一センサCentralへの参照は、当時の調査経緯を示す。
> これらのファイルは2026-07-17のcleanupで削除され、現行実装は独自cycle packetと
> `MultiUARTCentral`を使用する。

## 目的

2台または3台の Raspberry Pi Pico 2 W を使い、CSCS/CSCP に準拠しない
独自 BLE 通信でサイクルコンピュータ実験を行う。

- センサ側: Pico 2 W + MPU-6050/MPU-6500。回転検出結果を BLE Peripheral として送信する。
- ホスト側: Pico 2 W。BLE Central として受信し、タイヤ装着センサを前提に速度を計算する。
- ディスプレイ側: Pico 2 W + GC9A01。2台構成ではホスト側と同居してもよい。3台構成ではホスト側から SPI または I2C で速度値を受け取って表示する。
- 通信周期: まず 500 ms を目標にする。失敗時はログで原因を追えるようにする。
- 配置方針: UF2 に Ruby アプリを全部組み込まず、R2P2 で差し替えられる `/home` と `/lib` 向けの `.rb` を用意する。`.mrb` はこのリポジトリでは作らない。
- コミット/プッシュ: この TODO を確認してもらった後に行う。

## 調査結果

### 既存の tracked 実装

- `lib/mpu_6050.rb`
  - PicoRuby 向けの最小 MPU-6050 driver。
  - `sample` は配列や Hash を返さず、MPU オブジェクト自身に scalar reader を更新する。
  - 既定は gyro +/-2000 dps、accel +/-16 g、sample interval 10 ms。
- `lib/mpu_6050/rotation_detector.rb`
  - 1軸ジャイロ積分を中心に、低速時だけ加速度位相へ fallback する回転検出器。
  - `count`, `time_ms`, `delta_angle`, `angle`, `gyro_dps`, `phase_valid?`, `saturated?`, `dt_skipped?` を持つ。
  - センサ側では `delta_angle` を通知間隔ごとに積算して送るのが自然。
- `lib/ble_transport.rb`, `lib/ble_csc_service.rb`, `lib/mpu_6050_ble_csc.rb`
  - 既存の CSCS encoder / peripheral transport。
  - little-endian の固定長 String を再利用する方針が今回も使える。
  - 今回は CSCS UUID `0x1816` や CSC Measurement `0x2A5B` は使わない。
- `lib/ble_transport/picoruby_peripheral.rb`
  - PicoRuby の `BLE::GattDatabase`, `AdvertisingData`, `notify`, `pop_write_value`, `push_read_value` を使う peripheral 実装例。
  - CCCD を見て notification 有効状態を管理する実装は流用できる。
- `mrbgems/picoruby-gc9a01-speedometer`
  - `GC9A01SimpleSpeedometer#render(speed_kmh)` と `GC9A01Speedometer#render(speed_kmh, cadence_rpm)` が使える。
  - フルフレームバッファを使わない実装になっているため、BLE central と同居させる選択肢もある。
  - メモリや BLE 安定性を優先する場合は、GC9A01 専用 Pico 2 W に分離する。
- `docs/picoruby/gc9a01_speedometer.md`
  - Pico 2 W の GC9A01 組み込み後 Ruby heap は 364 KiB と記録されている。
  - Pico 2 W build config には `picoruby-ble`, `picoruby-ble-uart`, `picoruby-gc9a01-speedometer` が入る。
  - `patches/picoruby-gc9a01-speedometer.patch` の適用有無で GC9A01 あり/なし firmware を分けられる。
- `docs/mpu_6050/rotation_detector.ja.md`
  - 軸選択、デッドバンド、`dt_skipped?` の調整手順がまとまっている。
- `docs/spec.ja.md`, `docs/sensors.ja.md`
  - 標準 CSCS ではサイコンが counter と timestamp 差分から速度を計算する。
  - 今回は互換性より実験を優先し、独自 service と独自 payload にする。

### PicoRuby BLE 実装

- `tmp/picoruby/mrbgems/picoruby-ble`
  - Peripheral / Central / Observer / Broadcaster role がある。
  - Peripheral は GATT database, advertisement, CCCD write, notification を Ruby から扱える。
  - Central は scan, connect, service/characteristic discovery, descriptor write, notification event を扱える。
- `tmp/picoruby/mrbgems/picoruby-ble-uart/mrblib/ble_uart.rb`
  - Nordic UART Service 互換の peripheral/central 実装があり、central 側の state machine と `GATT_EVENT_NOTIFICATION` 解析が参考になる。
  - service UUID / RX UUID / TX UUID は initializer で差し替えられるため、NUS UUID ではなく独自 UUID で使える。
  - Peripheral / Central の advertise、scan、connect、discover、CCCD subscribe、notification 処理がまとまっているため、初期実装では `BLE::UART` を優先する。
  - 現行 `picoruby-ble` の `btstack_config.h` は `MAX_NR_HCI_CONNECTIONS 1` / `MAX_NR_GATT_CLIENTS 1` なので、センサ2台 + ホスト1台の同時接続は firmware 設定変更を含めて検証する。
- `BLE#start` は終了時に HCI power off する。
  - センサ/ホストの本番ループでは、起動時に power on し、ループ内で `pop_packet` / heartbeat を poll する形にする。

### メモリ制約

- BLE + GC9A01 + PicoRuby の同居は余裕が大きくないため、2台構成と3台構成を両方残す。
- 3台構成では、BLE host firmware から GC9A01 mrbgem を外し、display firmware だけに GC9A01 mrbgem を入れる。
- デフォルト ATT MTU 23 で 1 notification に載る値は 20 bytes なので、MTU 交渉に依存しない 20 byte 固定 frame にする。
- ループ中に避けるもの:
  - Hash / Array の生成。
  - 可変長文字列プロトコル。
  - `String#<< integer` による UTF-8 展開リスク。
  - 高頻度の長い serial log。
- ループ中に使うもの:
  - 事前確保した固定長 `String`。
  - `String#setbyte` による binary 書き込み。
  - 整数の fixed point payload。
  - serial log は状態遷移、通知、周期診断だけに制限する。

### git 管理外の参考ファイル

- `build/cscp_r2p2_app/home/app.rb` と `build/cscp_r2p2_app/lib/...` に、R2P2 `/home` + `/lib` 配置の CSCS 実機向けサンプルがある。
- ただし `build/` は `.gitignore` 対象で、tracked `lib/` と API 差分もある。
- 今回の実装では参考にするが、source of truth にはしない。

## 構成方針

### 2台構成

- センサ Pico 2 W: MPU-6050/MPU-6500 + BLE Peripheral。
- ホスト/表示 Pico 2 W: BLE Central + GC9A01。
- 利点: 配線と台数が少なく、最初の end-to-end 確認が早い。
- 注意: BLE と GC9A01 を同じ PicoRuby heap 上で動かすため、メモリと event loop の余裕を実測する。

### 3台構成

- センサ Pico 2 W: MPU-6050/MPU-6500 + BLE Peripheral。
- ホスト Pico 2 W: BLE Central。速度計算と serial debug を担当する。
- ディスプレイ Pico 2 W: GC9A01。ホストから受け取った速度だけを表示する。
- ホストからディスプレイへの通信は SPI または I2C を候補にする。
- 初期実装では I2C を第一候補にする。理由は、速度値の更新頻度が低く、配線と host/display の役割分担が単純なため。
- GC9A01 と BLE を分離できるため、最終的な安定性確認では3台構成を優先する。

## 採用する通信方式

初期実装では `BLE::UART` を優先する。UUID は NUS 互換の既定値ではなく、独自
128-bit UUID に差し替える。BLE 上は UART-style の byte stream として扱い、
アプリケーション層で 20 byte 固定 frame を切り出す。

- Service UUID: `6b3f0001-7a2d-4f6b-9af0-5c1a85f3d701`
- RX UUID: `6b3f0002-7a2d-4f6b-9af0-5c1a85f3d701`
- TX UUID: `6b3f0003-7a2d-4f6b-9af0-5c1a85f3d701`
- CCCD UUID: `0x2902`
- GAP name: `PRCycle`
- Advertisement:
  - Flags `0x06`
  - Complete or shortened local name `PRCycle`
  - Complete List of 128-bit Service UUIDs に上記 service UUID

専用 GATT characteristic は phase 2 の fallback とする。切り替える条件は次の通り。

- [ ] `BLE::UART` の stream buffer / `byteslice` / 文字列連結が実機 heap で問題になる。
- [ ] 20 byte frame parser で packet boundary や sequence gap を安定して扱えない。
- [ ] センサ2台 + ホスト1台の同時接続で、`BLE::UART` の単一接続前提が支配的な制約になる。
- [ ] host-to-display との同居で event loop latency が許容範囲を超える。

## Payload v1

20 bytes 固定、little-endian。MTU 23 でも 1 notification に収まるが、
`BLE::UART` では byte stream として受け取り、受信側 frame parser が 20 byte
単位で切り出す。

| Offset | Size | Type | Name | Meaning |
| ---: | ---: | --- | --- | --- |
| 0 | 1 | u8 | version | `1` |
| 1 | 1 | u8 | flags | bit field |
| 2 | 2 | u16 | sequence | notification ごとに increment |
| 4 | 4 | u32 | sensor_time_ms | sensor 側 monotonic ms |
| 8 | 4 | s32 | total_revolutions | 起動/subscribe 後の累積フル回転数 |
| 12 | 4 | s32 | delta_angle_mrad | 前回送信成功後の積算角。mrad。フル回転分も含む |
| 16 | 2 | u16 | interval_ms | 前回送信成功からの sensor 側経過 ms |
| 18 | 2 | u16 | status | debug/status bit field |

`flags`:

- bit 0: first packet after subscribe/reset
- bit 1: angle value valid
- bit 2: rotation count changed in this interval
- bit 3: detector saturated in this interval
- bit 4: dt skipped in this interval
- bit 5: I2C error seen in this interval
- bit 6: signed speed should be preserved
- bit 7: reserved

`status`:

- bits 0..7: sample count modulo 256
- bits 8..15: I2C error count modulo 256

ホスト側の速度計算は `delta_angle_mrad` と `interval_ms` を主に使う。
`total_revolutions` は抜けや方向診断のために保持する。

```text
wheel_rotations = delta_angle_mrad / 1000.0 / (2 * PI)
distance_m = wheel_rotations * wheel_circumference_m
speed_kmh = abs(distance_m / (interval_ms / 1000.0)) * 3.6
```

ホイールの回転数はケイデンスとして扱わない。専用ケイデンスセンサを追加するまでは
ホストのケイデンス値を`0.0 rpm`に固定する。

## 実装ステップ

### 0. 作業前確認

- [x] `git status --short` を確認し、既存の未追跡 `task_cscp.md` を触らない。
- [x] `BLE_TODO.md` の内容をユーザーが確認するまで commit/push しない。
- [x] 実装時の対象 firmware は Pico 2 W / R2P2 / PicoRuby とし、`.mrb` 生成は行わない。

### 0.5. Firmware build 方針

- [x] GC9A01 なし firmware を BLE センサ用/ホスト用の基本 build にする。
- [ ] GC9A01 あり firmware をディスプレイ用、または2台構成のホスト/表示兼用 build にする。
- [ ] `tmp/picoruby` はクリーンな基準 checkout として保つ。
- [ ] GC9A01 あり build は、別の作業 tree か clone で `patches/picoruby-gc9a01-speedometer.patch` を適用して行う。
- [x] GC9A01 なし build では同 patch を適用しない。
- [ ] build 手順書に、どの board にどの UF2 を書くかを明記する。
- [ ] build 後に PicoRuby checkout の `git status --short` を確認し、意図しない patch 適用状態を残さない。

### 1. 共通 packet codec

- [x] `lib/ble_cycle_packet.rb` を追加する。
- [x] UUID、payload size、flag/status 定数を定義する。
- [x] `bytes(n)`, `put_u8`, `put_u16`, `put_u32`, `put_s32`, `get_u16`, `get_u32`, `get_s32` を実装する。
- [x] `encode_into(payload, ...)` を実装し、呼び出し側が渡した 20 byte String を破壊的に更新する。
- [x] `decode(payload, out)` を実装する。ホスト実機では Hash を返さず、渡された軽量オブジェクトか instance variables に展開できる形にする。
- [x] `BLE::UART` の stream から 20 byte frame を切り出す `FrameReader` を追加する。
- [x] `FrameReader` は 20 byte 未満を保持し、40 byte 以上を連続 frame として処理できるようにする。
- [x] sequence gap と invalid version を検出できるようにする。
- [x] `test/ble_cycle_packet_test.rb` を追加し、byte layout、signed 32-bit、sequence rollover、invalid length を CRuby で確認する。
- [ ] `test/ble_cycle_frame_reader_test.rb` を追加し、分割受信、連結受信、余剰 byte、invalid frame を確認する。

### 2. センサ側 BLE::UART peripheral

- [x] `lib/ble_cycle_sensor/uart_peripheral.rb` を追加する。
- [x] `BLE::UART.new(role: :peripheral, name: "PRCycle", service_uuid: ..., rx_uuid: ..., tx_uuid: ...)` を使う。
- [x] advertisement が 31 bytes に収まることをテストまたは起動時チェックで確認する。
- [x] センサ app の loop から `uart.start` の block または同等の poll loop を使い、MPU sampling を止めない構成にする。
- [x] 事前確保した 20 byte payload を `uart.write(payload)` で送る。
- [x] `uart.connected?` と debug log で connect / disconnect / subscribe 相当の状態を追う。
- [x] serial log は connect / write / disconnect / dropped event count に限定する。
- [x] 専用 GATT peripheral は `BLE::UART` で問題が出た場合の fallback として後回しにする。

### 3. センサ側 R2P2 app

- [x] tracked な copy-ready 配置として `r2p2_apps/ble_cycle_sensor/home/app.rb` を追加する。
- [x] 必要な Ruby lib を `r2p2_apps/ble_cycle_sensor/lib/` に置くか、転送手順で root `lib/` から `/lib` へ入れることを明記する。
- [x] 起動時定数を app 冒頭に集約する。
  - [x] I2C unit / SDA / SCL。
  - [ ] MPU sample period。
  - [x] rotation axis / direction / min period / deadband。
  - [x] notify period `500` ms。
  - [x] `DEBUG_LOG`。
- [x] `mpu.calibrate_gyro` 後に loop を開始する。
- [ ] 5..10 ms 周期で `mpu.sample` と `detector.update` を行う。
- [x] 毎サンプル `detector.delta_angle` を `delta_angle_since_notify` に積算する。
- [x] `detector.count` から累積フル回転数を更新する。
- [x] subscribe 直後は `first packet` として `delta_angle_mrad = 0`, `interval_ms = 0` を送り、速度スパイクを防ぐ。
- [ ] `uart.write(payload)` 成功後だけ delta angle、sample count、interval status を reset する。
- [x] I2C error は短期的には status bit に載せ、連続エラー上限を超えたら raise して serial で分かるようにする。

### 4. ホスト側 BLE::UART central

- [x] `lib/ble_cycle_host/uart_central.rb` を追加する。
- [x] `BLE::UART.new(role: :central, service_uuid: ..., rx_uuid: ..., tx_uuid: ...)` を使う。
- [x] 最初は device name、BLE address、または service UUID の hardcode で自動接続する。複数候補選択 UI は後続タスクに分ける。
- [x] `uart.available?` / `uart.read_nonblock` で受信し、`FrameReader` に渡す。
- [x] 20 byte frame ごとに packet codec で decode し、速度計算へ渡す。
- [ ] 不正 length、invalid version、重複 sequence、sequence gap、disconnect を serial log に出す。
- [ ] 専用 central state machine は `BLE::UART` で問題が出た場合の fallback として後回しにする。

### 4.5. センサ2台 + ホスト1台の BLE::UART 検証

- [ ] 現行 firmware の `MAX_NR_HCI_CONNECTIONS 1` / `MAX_NR_GATT_CLIENTS 1` で、同時接続が不可能であることを確認する。
- [ ] PicoRuby BLE firmware 側の設定を `MAX_NR_HCI_CONNECTIONS 2` / `MAX_NR_GATT_CLIENTS 2` へ増やせるか確認する。
- [ ] `BLE::UART` central を multi-slot 化し、connection handle、peer RX/TX/CCCD handle、FrameReader、last sequence をセンサごとに分けられるか試す。
- [ ] 2台同時 notify で 500 ms 周期が維持できるか、event queue drop と heap 使用を確認する。
- [ ] 同時接続が難しい場合は、以下の順で代替を検討する。
  - [ ] ホストがセンサへ順番に接続して値を読む方式。
  - [ ] スピードセンサとケイデンスセンサを1台のセンサ Pico にまとめる方式。
  - [ ] 複数 BLE host を用意し、display 側で値を統合する方式。
  - [ ] BTstack / PicoRuby BLE port への複数接続 patch。

### 5. ホスト側速度計算

- [x] `lib/ble_cycle_host/speed_estimator.rb` を追加する。
- [x] wheel circumference はホスト側定数 `WHEEL_CIRCUMFERENCE_MM` として持つ。
- [x] `delta_angle_mrad` と `interval_ms` から `speed_kmh` を計算する。
- [x] 停止判定を入れる。
  - [x] 一定時間 notification が来ない場合は速度を 0 に落とす。
  - [x] notification は来ているが `delta_angle_mrad == 0` が続く場合も 0 にする。
- [x] 必要なら小さい IIR smoothing を入れる。ただし最初は raw speed を優先して遅延を増やさない。
- [x] `test/ble_cycle_speed_estimator_test.rb` で 0 km/h、正回転、逆回転、interval 0、sequence gap を確認する。

### 6. ホスト側 R2P2 app と表示出力

- [x] tracked な copy-ready 配置として `r2p2_apps/ble_cycle_host/home/app.rb` を追加する。
- [x] ホスト app は BLE 受信と速度計算を担当し、GC9A01 へ直接依存しない形を第一候補にする。
- [x] 2台構成を選ぶ場合だけ、同じ app から `GC9A01SimpleSpeedometer` へ直接 `render(speed_kmh)` する adapter を使う。
- [x] 3台構成を選ぶ場合、ホスト側は表示 Pico へ速度値を UART で送る。SPI/I2C は PicoRuby/R2P2 の slave API が使えるようになった後で差し替える。
- [x] host-to-display の最小 payload を決める。
  - [x] version `u8`
  - [x] sequence `u16`
  - [x] speed_centi_kmh `u16`
  - [x] status `u8`
- [x] I2C 方式では、表示 Pico を I2C peripheral/slave にできるか PicoRuby/R2P2 API を確認する。難しい場合は SPI または UART へ切り替える。
- [x] BLE 受信のたびに `speed_kmh` を更新し、表示側への送信は 5..15 Hz 程度に制限する。
- [x] serial log に connection state、sequence、interval、delta angle、speed_kmh、RSSI が取れる場合は RSSI を出す。
- [x] 受信なし timeout、service 不一致、subscribe 失敗を速度計表示または serial で分かるようにする。

### 6.5. ディスプレイ側 R2P2 app

- [x] tracked な copy-ready 配置として `r2p2_apps/ble_cycle_display/home/app.rb` を追加する。
- [x] GC9A01 あり firmware で動かす前提にする。
- [x] `require 'gc9a01_speedometer'` または `require 'gc9a01_demo_config'` の要否を firmware に合わせて確認する。
- [x] GC9A01 pin/frequency/brightness 定数を app 冒頭に集約する。
- [x] `GC9A01SimpleSpeedometer` を第一候補にする。
- [x] ホストから受け取った `speed_centi_kmh` を `speed_kmh` に戻して `render(speed_kmh)` する。
- [x] 受信 timeout 時は速度を 0 に落とし、serial に timeout を出す。
- [x] 2台構成ではこの app は使わず、ホスト app の display adapter を使う。

### 7. R2P2 配置ドキュメント

- [ ] `docs/ble/custom_cycle_demo.ja.md` を追加する。
- [ ] センサ側 `/home/app.rb` と `/lib/*.rb` の配置を記載する。
- [ ] ホスト側 `/home/app.rb` と `/lib/*.rb` の配置を記載する。
- [ ] ディスプレイ側 `/home/app.rb` と `/lib/*.rb` の配置を記載する。
- [ ] `.mrb` は作らず、ユーザーが Pico へ転送するときにコンパイルする前提を書く。
- [ ] GC9A01 なし UF2 と GC9A01 あり UF2 の作り分けを記載する。
- [ ] `tmp/picoruby` をクリーンに保ち、GC9A01 patch は別 tree へ適用する方針を書く。
- [ ] 2台構成と3台構成の起動順序を書く。
  - [ ] センサ側を先に起動。
  - [ ] 3台構成ではディスプレイ側を起動して受信待ちにする。
  - [ ] ホスト側を起動し、scan/connect/subscribe と display link を確認。
- [ ] MPU 配線、GC9A01 配線、host-to-display 配線、wheel circumference、axis tuning を記載する。
- [ ] 正常 serial log と代表的な異常 log を記載する。

### 8. 検証

- [x] `ruby -Ilib test/ble_cycle_packet_test.rb`
- [x] `ruby -Ilib test/ble_cycle_display_packet_test.rb`
- [ ] `ruby -Ilib test/ble_cycle_frame_reader_test.rb`
- [x] `ruby -Ilib test/ble_cycle_speed_estimator_test.rb`
- [ ] 既存テスト `ruby -Ilib test/ble_csc_service_test.rb`
- [ ] syntax check:
  - [x] `ruby -c lib/ble_cycle_packet.rb`
  - [x] `ruby -c lib/ble_cycle_sensor/uart_peripheral.rb`
  - [x] `ruby -c lib/ble_cycle_host/uart_central.rb`
  - [x] `ruby -c lib/ble_cycle_display_packet.rb`
  - [x] `ruby -c lib/ble_cycle_host/display_output.rb`
  - [x] `ruby -c r2p2_apps/ble_cycle_sensor/home/app.rb`
  - [x] `ruby -c r2p2_apps/ble_cycle_host/home/app.rb`
  - [x] `ruby -c r2p2_apps/ble_cycle_display/home/app.rb`
- [ ] PicoRuby host build がある場合、`tmp/picoruby/build/host/bin/picoruby` で packet codec の smoke test を行う。
- [ ] センサ側だけを起動し、スマートフォン BLE scanner で以下を確認する。
  - [ ] name `PRCycle`
  - [ ] custom 128-bit service UUID
  - [ ] custom UART RX/TX characteristics
  - [ ] CCCD
  - [ ] subscribe 後 500 ms 付近で notification
- [ ] 2台実機で以下を確認する。
  - [x] sensor subscribe 直後に first packet が出る。
  - [x] wheel を回すと `delta_angle_mrad` と `speed_kmh` が増える。
  - [ ] 停止後、速度が 0 へ落ちる。
  - [ ] 30秒以上、event queue drop / overrun / NoMemoryError が出ない。
  - [ ] disconnect 後に sensor が re-advertise し、host が再接続できる。
- [ ] 3台実機で以下を確認する。
  - [ ] host が BLE 受信と速度計算だけで安定動作する。
  - [ ] host-to-display link で sequence gap と timeout を検出できる。
  - [ ] display Pico が受信速度を GC9A01 へ表示する。
  - [ ] BLE host firmware に GC9A01 mrbgem が入っていない構成で動作する。
- [ ] センサ2台 + ホスト1台の実機検証を行う。
  - [ ] 同時接続できるか。
  - [ ] 同時接続できる場合、speed/cadence の両方が 500 ms 目標で更新できるか。
  - [ ] 同時接続できない場合、代替構成を選んで TODO を更新する。

## 完了条件

- [x] CSCS/CSCP UUID を使わず、custom BLE service の UART-style TX notification で 20 byte frame を送受信できる。
- [x] 初期実装では `BLE::UART` と独自 UUID を使い、20 byte 固定 frame を送受信できる。
- [x] センサ側は MPU の回転検出から累積回転数と前回通信後の回転角を 500 ms 目標で送る。
- [ ] ホスト側は受信 payload から速度を計算し、2台構成では直接、3台構成では SPI/I2C 経由で GC9A01 speedometer に渡す。
- [x] センサ側/ホスト側の両方に serial debug output がある。
- [ ] 3台構成を選ぶ場合、ディスプレイ側にも serial debug output がある。
- [ ] Pico 2 W のメモリ制約を意識し、ループ中の不要な allocation を避けている。
- [x] R2P2 の `/home` と `/lib` に置ける `.rb` が用意され、`.mrb` は生成していない。
- [ ] GC9A01 あり/なし firmware の build 手順が分かれ、クリーンな PicoRuby checkout に意図しない patch 状態を残していない。
- [x] 実装後、ユーザー確認を受けてから commit/push する。

## 未決事項

- [x] wheel circumference の初期値。仮値は `2105` mm とし、app 冒頭で変更可能にする。
- [ ] センサの実機取り付け軸。初期値は検証用 `examples/mpu_6050_rotation_verify.rb` で決める。
- [ ] 速度は絶対値表示を初期値にする。逆回転を見たい場合だけ signed 表示へ切り替える。
- [ ] 複数センサが見つかった場合の選択 UI は、最初の自動接続が安定してから追加する。
- [ ] PicoRuby BLE central 側で descriptor write / notification が不安定な場合、`picoruby-ble` への最小 patch が必要か判断する。

## 今後の拡張

- [ ] スピードセンサに加えて、ケイデンスセンサ用の同一 custom service/profile を追加する。
- [ ] センサ2台 + ホスト1台構成を扱えるよう、host central の接続先を複数スロット化する。
- [ ] 最初の複数センサ対応では BLE address / device name / role を hardcode し、scan UI や pairing UI は後回しにする。
- [ ] 複数接続が firmware 設定だけで成立するなら `BLE::UART` を継続し、成立しない場合だけ専用 GATT / BTstack patch / 構成変更を検討する。
- [ ] Payload v2 で sensor role を追加する。
  - [ ] `1`: wheel speed sensor
  - [ ] `2`: cadence sensor
- [ ] ホスト側 speed estimator と cadence estimator を分け、GC9A01Speedometer の `render(speed_kmh, cadence_rpm)` へ渡せるようにする。

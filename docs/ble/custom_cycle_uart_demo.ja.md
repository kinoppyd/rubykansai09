# BLE::UART custom cycle demo

最終更新: 2026-07-09 JST

## 目的

2台の Raspberry Pi Pico 2 W で、独自 UUID の `BLE::UART` を使い、
センサ側からホスト側へ 20 byte 固定 frame が届くことを確認する。

この手順では GC9A01 は使わない。ホスト側は受信値を USB serial に出力する。
センサ側は初期状態で fake 回転データを送るため、MPU-6050 なしでも BLE 経路を
先に確認できる。

## 前提 firmware

両方の Pico 2 W に、GC9A01 なしの R2P2/PicoRuby firmware を書き込む。

必要な mrbgem:

- `picoruby-ble`
- `picoruby-ble-uart`
- `picoruby-cyw43`

GC9A01 の確認は後続手順で行うため、この BLE 疎通確認では
`patches/picoruby-gc9a01-speedometer.patch` を適用した firmware は不要。

## センサ側へ配置するファイル

R2P2 の `/lib`:

```text
lib/ble_cycle_packet.rb
lib/ble_cycle_sensor/uart_peripheral.rb
```

R2P2 の `/home/app.rb`:

```text
r2p2_apps/ble_cycle_sensor/home/app.rb
```

このリポジトリでは `.mrb` は生成しない。Pico 2 W へ転送するときに、
利用中の R2P2 転送手順で compile する。

## ホスト側へ配置するファイル

R2P2 の `/lib`:

```text
lib/ble_cycle_packet.rb
lib/ble_cycle_host/advertising_report.rb
lib/ble_cycle_host/uart_central.rb
lib/ble_cycle_host/uart_central_patch.rb
lib/ble_cycle_host/speed_estimator.rb
```

R2P2 の `/home/app.rb`:

```text
r2p2_apps/ble_cycle_host/home/app.rb
```

ホスト側 app の `DEVICE_ADDRESS` は、センサ側ログの
`UART Peripheral up on: ...` に出た address に合わせる。

## 起動順

1. センサ側 Pico 2 W を起動する。
2. センサ側 serial で次のような起動ログを確認する。

```text
BLE cycle sensor
mode
fake
```

3. ホスト側 Pico 2 W を起動する。
4. ホスト側が custom service UUID または device name `PRCycle` を advertise しているセンサへ自動接続する。
5. センサ側に `ble_connected` と `TX` が出ることを確認する。
6. ホスト側に `RX` と `speed_kmh` が出ることを確認する。

## 期待ログ

センサ側:

```text
UART Peripheral up on: `88:A2:9E:xx:xx:xx`
Advertising started
ble_connected
1
TX
seq
0
delta_mrad
0
interval_ms
0
TX
seq
1
delta_mrad
3142
interval_ms
500
```

ホスト側:

```text
BLE cycle host
wheel_circumference_mm
2105
target_name
PRCycle
UART Central up on: `88:A2:9E:xx:xx:xx`
Scan started
scan_state
TC_W4_SCAN_RESULT
scan_reports
0
Found cycle UART device
name_match
1
service_match
0
gap_connect
0
Connected. Handle: 0x0040
NUS central ready
ble_connected
1
RX
count
1
seq
0
speed_kmh
0.0
RX
count
2
seq
1
delta_mrad
3142
speed_kmh
7.57
```

`interval_ms` は実際の event loop により 500 ms から多少ずれてよい。
`reader_gap_count` が増え続ける場合は、BLE frame の抜けまたは decode ずれを
疑う。

`service_match 0` かつ `name_match 1` でも接続できていれば、この段階では問題ない。
これは advertising report に custom service UUID が含まれない、または central 側で
拾えない場合の bring-up 用 fallback である。

## 接続できない場合の切り分け

- ホスト側に `Scan started` が出ない場合は、central の HCI 起動または `/lib` 配置を確認する。
- `scan_reports` が増えない場合は、ホストが advertising report を受け取れていない。
- `scan_reports` は増えるが `Found cycle UART device` が出ない場合は、センサ側の device name が `PRCycle` で起動しているか、ホスト側の `DEVICE_NAME` と一致しているかを確認する。
- `Found cycle UART device` が出て `gap_connect` が `0` ではない場合は、address type や接続パラメータ側の問題を疑う。
- `Connected. Handle` は出るが `NUS central ready` が出ない場合は、GATT service / characteristic discovery または CCCD write の失敗を疑う。

## scan report が 0 の場合

ホスト側で `scan_reports` が 0 のままの場合、`BLE::UART` の接続処理へ進む前に
raw central scan だけを確認する。

ホスト側 Pico 2 W の `/lib` に `lib/ble_cycle_host/advertising_report.rb` を配置し、
`/home/app.rb` として次を一時的に配置する。

```text
r2p2_apps/ble_cycle_scan/home/app.rb
```

診断 app の `TARGET_ADDRESS` も、センサ側ログの address に合わせる。

センサ側を起動して `Advertising started` が出ている状態で、この診断 app を起動する。

期待ログ:

```text
BLE cycle scan debug
target_name
PRCycle
scan_debug_up
88:A2:9E:xx:xx:xx
scan_started
adv_report
count
1
addr
88:A2:9E:xx:xx:xx
name
PRCycle
address_match
1
name_match
1
```

`scan_status` の `reports` が増えない場合、ホスト側 firmware / controller / RF の
scan 動作が成立していない。`adv_report` は出るが `name_match` が 0 の場合、
センサ側の advertised name とホスト側の `TARGET_NAME` が一致していない。
今回のようにセンサ address は見えるが `name` と `service128_len` が空の場合は、
`address_match 1` であれば通常のホスト app が address fallback で接続を試みる。
ただし `event_type 4` は scan response なので接続対象にはしない。通常のホスト app は
同じ address の connectable report を待ってから `gap_connect` する。

`le_meta` / `2` が出続ける場合は、raw HCI の LE Advertising Report が届いている。
最新の `lib/ble_cycle_host/advertising_report.rb` と
`r2p2_apps/ble_cycle_scan/home/app.rb` を配置し直すと `adv_report` として表示される。

## MPU-6050 を使う場合

BLE 経路確認後、センサ側 app 冒頭の定数を変更する。

```ruby
USE_MPU = true
```

必要に応じて次も実機配線に合わせる。

```ruby
I2C_UNIT = :RP2040_I2C1
SDA_PIN = 2
SCL_PIN = 3
AXIS = :y
DIRECTION = 0
```

軸は `examples/mpu_6050_rotation_verify.rb` で `max_gyro_x/y/z` を確認して決める。

## 既知の制限

- `BLE::UART` は byte stream なので、受信側は `FrameReader` で 20 byte frame を切り出す。
- 現行 PicoRuby BLE firmware は `MAX_NR_HCI_CONNECTIONS 1` / `MAX_NR_GATT_CLIENTS 1` のため、センサ2台同時接続は別途検証が必要。
- この手順は BLE 疎通確認用であり、GC9A01 表示や host-to-display 通信はまだ含まない。

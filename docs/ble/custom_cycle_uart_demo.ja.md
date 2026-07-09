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
lib/ble_cycle_host/uart_central.rb
lib/ble_cycle_host/speed_estimator.rb
```

R2P2 の `/home/app.rb`:

```text
r2p2_apps/ble_cycle_host/home/app.rb
```

## 起動順

1. センサ側 Pico 2 W を起動する。
2. センサ側 serial で次のような起動ログを確認する。

```text
BLE cycle sensor
mode
fake
```

3. ホスト側 Pico 2 W を起動する。
4. ホスト側が custom service UUID を advertise しているセンサへ自動接続する。
5. センサ側に `ble_connected` と `TX` が出ることを確認する。
6. ホスト側に `RX` と `speed_kmh` が出ることを確認する。

## 期待ログ

センサ側:

```text
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

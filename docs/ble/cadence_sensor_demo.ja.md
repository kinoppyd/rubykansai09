# 専用ケイデンスセンサの確認手順

最終更新: 2026-07-17 JST

## 目的

Raspberry Pi Pico 2 WとMPU-6050をクランク側の専用センサとして使い、
独自`BLE::UART` serviceから250 ms周期で回転角を通知する。
GAP nameは`PRCad`で、packet形式はスピードセンサと同じ
`BLECyclePacket` v1（20 bytes）を使う。

## 配線

| MPU-6050 | Pico 2 W | 用途 |
| --- | --- | --- |
| VCC | 3V3(OUT) | 3.3 V電源 |
| GND | GND | ground |
| SDA | GP2 | I2C1 SDA |
| SCL | GP3 | I2C1 SCL |

`r2p2_apps/ble_cycle_sensor/home/app.rb`先頭の`I2C_UNIT`、
`SDA_PIN`、`SCL_PIN`を変更すれば別のI2C配線も使用できる。

## R2P2への配置

`/home/app.rb`として配置するsource:

```text
r2p2_apps/ble_cycle_sensor/home/app.rb
```

`/lib`へ配置するsource:

```text
lib/ble_cycle_packet.rb
lib/ble_cycle_sensor/uart_peripheral.rb
lib/mpu_6050.rb
lib/mpu_6050/rotation_detector.rb
```

`SENSOR_ROLE = :cadence`へ変更してから`app.mrb`を生成する。`machine`、`i2c`、
`BLE::UART`はUF2に含まれるmrbgemを使う。このリポジトリには転送前のRuby sourceだけを
置き、`.mrb`はcommitしない。

## 起動とBLEを確認する

1. 電源を切ってMPU-6050を配線する。
2. `SENSOR_ROLE = :cadence`にした`app.mrb`と必要なlibraryを配置する。
3. 静止した状態で起動し、`calibrating`中はセンサを動かさない。
4. `mpu_ready`の後にadvertisingが始まることを確認する。
5. Serial logで`PRCad`のaddressを記録する。
6. Hostから接続し、`TX`が約250 ms間隔で増えることを確認する。
7. クランクを回し、`delta_mrad`、`total_rev`、`flags`の変化を確認する。

期待する起動ログ:

```text
BLE cycle sensor
sensor_role
cadence
calibrating
mpu_ready
UART Peripheral up on: `88:A2:9E:xx:xx:xx`
Advertising started
```

MPU-6050が未接続、またはI2C初期化に失敗した場合はfake値へfallbackせず、次を出して
advertising前に停止する。

```text
mpu_init_failed
I2C error message
```

## MPU-6050の調整

1. 1回転の向きや計数が合わなければ、app先頭の`AXIS`と`DIRECTION`を調整する。
2. 静止時の揺れを回転として拾う場合は`GYRO_DEADBAND_DPS`を調整する。
3. Speedとcadenceで取付方向が異なる場合は、role別の定数選択を統合app内へ追加する。

`FLAG_FIRST`、`FLAG_ANGLE_VALID`、`FLAG_ROTATION_CHANGED`、
`FLAG_I2C_ERROR`、`FLAG_SATURATED`、`FLAG_DT_SKIPPED`の意味は
スピードセンサと共通である。連続I2C errorが
`MAX_CONSECUTIVE_I2C_ERRORS`へ達した場合は処理を停止する。

## Debug LED

統合appは既定でGP25をactive highのdebug LEDとして使う。起動時に一度点灯し、BLE接続後は
20 byte packetを送るたびに約30 ms点灯する。Advertising中や未接続時は送信パルスを出さない。

- 使用pinは`DEBUG_LED_PIN`で変更する。
- Active levelは`DEBUG_LED_ACTIVE`で変更する。
- 点灯時間は`DEBUG_LED_PULSE_MS`で変更する。
- LEDを使わない場合は`DEBUG_LED_ENABLED = false`にする。
- 外付けLEDを使う場合は適切な直列抵抗を入れる。

点灯処理は`sleep`を使わない。LED点灯中もMPU samplingとBLE event処理を継続する。

## 2センサhostへ接続するときの記録

次の2値をhost appの固定slot設定へ反映する。

```text
role: cadence
name: PRCad
address: センサ側の「UART Peripheral up on」に表示された値
```

GAP addressはPico 2 W個体ごとに異なる。スピードセンサの`PRCycle` addressを
ケイデンスslotへ設定しないこと。

## 3台構成で使うUF2

2026-07-11にPicoRuby `b0c1c4828b82b267dab9cabf4a372c46c2a1075e`、
Pico SDK 2.2.0 (`a1438dff1d38bd9c65dbd693f0e5db4b9ae91779`)からbuildした。
生成物はgit管理外の`tmp/uf2`にある。

| Pico 2 W | UF2 | 用途 |
| --- | --- | --- |
| Speed sensor | `R2P2-PICORUBY-PICO2_W-CYCLE-SENSOR-20260711-b0c1c482.uf2` | Clean、BTstack 1 connection |
| Cadence sensor | speedと同じsensor UF2 | 統合appを`SENSOR_ROLE = :cadence`にする |
| Host、画面なし | `R2P2-PICORUBY-PICO2_W-CYCLE-HOST-2CONN-20260711-b0c1c482.uf2` | BLEだけの切り分け用 |
| Host、2画面 | `R2P2-PICORUBY-PICO2_W-CYCLE-HOST-2CONN-DUAL-GC9A01-20260711-b0c1c482.uf2` | BLE + speed/cadence GC9A01 |

SHA-256とbuild結果:

| UF2 | SHA-256 | UF2 size | ELF text | ELF BSS | Heap limitまで |
| --- | --- | ---: | ---: | ---: | ---: |
| Sensor | `a7c4cb009a07a045e54cbb29d5043108d7c1c6d142627428aeda3610267d64bf` | 4500480 | 2259168 | 442124 | 49268 |
| Host、画面なし | `02d93455b4265e7f4a7b455e1d69f6ddf4162b63fa9c21b212b6f15ace9248e5` | 4503040 | 2260288 | 443128 | 48264 |
| Host、2画面 | `0d30e5d2eac86c6115868427f6338b094a94c3ab557fa916d96f70a1263d5666` | 4690432 | 2354052 | 444748 | 46180 |

Sensor UF2はspeed/cadenceの両方へ同じものを書き込む。Host用2接続patchをsensorへ
適用しない。画面なしhost UF2は、2画面描画とBLEの同居が不安定な場合の切り分けに使う。

## Speed sensorへのR2P2配置

Sourceと転送先:

```text
r2p2_apps/ble_cycle_sensor/home/app.rb       -> /home/app.mrb
lib/ble_cycle_packet.rb                      -> /lib/ble_cycle_packet.mrb
lib/ble_cycle_sensor/uart_peripheral.rb      -> /lib/ble_cycle_sensor/uart_peripheral.mrb
lib/mpu_6050.rb                              -> /lib/mpu_6050.mrb
lib/mpu_6050/rotation_detector.rb            -> /lib/mpu_6050/rotation_detector.mrb
```

統合appを`SENSOR_ROLE = :speed`にする。これによりGAP nameは`PRCycle`になる。

## Cadence sensorへのR2P2配置

Sourceと転送先:

```text
r2p2_apps/ble_cycle_sensor/home/app.rb       -> /home/app.mrb
lib/ble_cycle_packet.rb                      -> /lib/ble_cycle_packet.mrb
lib/ble_cycle_sensor/uart_peripheral.rb      -> /lib/ble_cycle_sensor/uart_peripheral.mrb
lib/mpu_6050.rb                              -> /lib/mpu_6050.mrb
lib/mpu_6050/rotation_detector.rb            -> /lib/mpu_6050/rotation_detector.mrb
```

統合appを`SENSOR_ROLE = :cadence`にする。これによりGAP nameは`PRCad`になる。
Speed/cadenceともMPU-6050は必須であり、fake modeはない。

## Multi-central hostへのR2P2配置

Sourceと転送先:

```text
r2p2_apps/ble_cycle_host/home/app.rb              -> /home/app.mrb
lib/ble_cycle_packet.rb                           -> /lib/ble_cycle_packet.mrb
lib/ble_cycle_host/advertising_report.rb          -> /lib/ble_cycle_host/advertising_report.mrb
lib/ble_cycle_host/notification_event.rb          -> /lib/ble_cycle_host/notification_event.mrb
lib/ble_cycle_host/multi_uart_transport.rb        -> /lib/ble_cycle_host/multi_uart_transport.mrb
lib/ble_cycle_host/multi_uart_central.rb          -> /lib/ble_cycle_host/multi_uart_central.mrb
lib/ble_cycle_host/speed_estimator.rb             -> /lib/ble_cycle_host/speed_estimator.mrb
lib/ble_cycle_host/cadence_estimator.rb           -> /lib/ble_cycle_host/cadence_estimator.mrb
lib/ble_cycle_host/display_output.rb              -> /lib/ble_cycle_host/display_output.mrb
```

実機addressをhost app先頭へ設定する。

```ruby
SPEED_DEVICE_ADDRESS = "PRCycle側ログのaddress"
CADENCE_DEVICE_ADDRESS = "PRCad側ログのaddress"
```

Cadence addressを確認する最初の起動だけは`CADENCE_DEVICE_ADDRESS = nil`でよい。
この場合は`PRCad` nameでslotを選ぶ。確認後は誤接続を避けるためaddressへ置き換える。

2台のGC9A01配線と画面側の定数は
[BLEサイクルホストのGC9A01 2画面構成](dual_gc9a01_cycle_host.ja.md)を参照する。

## Host firmware patch順

Clean PicoRuby treeとは別のhost build treeを作り、次の順序で適用する。この順序で
5 patchを連続適用できることを確認済みである。

```text
picoruby-ble-passive-scan.patch
picoruby-ble-notification-listeners.patch
picoruby-ble-central-event-delivery.patch
picoruby-ble-two-connections.patch
picoruby-gc9a01-speedometer.patch       # 2画面hostだけ
```

GC9A01なしhostでは最後のpatchとGC9A01 mrbgemを含めない。Sensor build treeには
どのhost patchも適用しない。

## 期待するhostログ

以下はevent名と確認箇所を示す代表例であり、address、connection handle、時刻、値は
実機ごとに異なる。

両slotがreadyになるまで:

```text
multi_central_up
scan_started
connecting_role
speed
connected_role
speed
connection_handle
64
ready_role
speed
scan_started
connecting_role
cadence
connected_role
cadence
connection_handle
65
ready_role
cadence
```

正常受信では`role`が交互に現れ、異なるconnection handleへ配送される。

```text
RX
role
speed
connection_handle
64
seq
10
speed_kmh
18.4
cadence_rpm
0.0
RX
role
cadence
connection_handle
65
seq
7
speed_kmh
18.4
cadence_rpm
72.1
```

Cadence側を再起動した場合、speed slotはreadyのまま維持される。

```text
disconnected_role
cadence
scan_started
ble_slot
cadence
slot_state
missing
cadence_rpm
0.0
connecting_role
cadence
ready_role
cadence
```

接続中にnotificationが1500 ms以上止まると、そのroleだけtimeoutする。

```text
timeout_role
cadence
display_tx
speed_kmh
18.4
cadence_rpm
0.0
```

`reader_gap_count`が増える場合はnotification欠落を示す。`reader_dropped`が増える場合は
20-byte frame境界または破損byteを確認する。

## 実機検証順

1. 統合appを`:speed`にした実機1台でhostのspeed slotをreadyにする。
2. 統合appを`:cadence`にした実機1台でhostのcadence slotをreadyにする。
3. 両sensorを接続し、handleが2個あり、各`interval_ms`が200..350 ms程度か確認する。
4. 静止時は0 rpm、クランク約1回転/秒で約60 rpmになることを確認する。
5. 各TXで対応するsensorのdebug LEDが短く点灯することを確認する。
6. Speedだけを再起動し、cadence RXと画面が継続することを確認する。
7. Cadenceだけを再起動し、speed RXと画面が継続することを確認する。
8. Host先行、sensor先行、speed/cadence逆順の各起動順を確認する。
9. `DEBUG_RX = false`、`DEBUG_DISPLAY = false`にして30分、その後可能なら2時間動作させる。
10. `NoMemoryError`、unexpected disconnect、sequence gapを記録する。

実機結果を得るまでは`CADENCE_TODO.md`の段階的検証と長時間検証を完了扱いにしない。

# 専用ケイデンスセンサの確認手順

最終更新: 2026-07-14 JST

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

`r2p2_apps/ble_cycle_cadence_sensor/home/app.rb`先頭の`I2C_UNIT`、
`SDA_PIN`、`SCL_PIN`を変更すれば別のI2C配線も使用できる。

## R2P2への配置

`/home/app.rb`として配置するsource:

```text
r2p2_apps/ble_cycle_cadence_sensor/home/app.rb
```

`/lib`へ配置するsource:

```text
lib/ble_cycle_packet.rb
lib/ble_cycle_sensor/uart_peripheral.rb
lib/mpu_6050.rb
lib/mpu_6050/rotation_detector.rb
```

`machine`、`i2c`、`BLE::UART`はUF2に含まれるmrbgemを使う。このリポジトリには
転送前のRuby sourceだけを置き、`.mrb`はcommitしない。

## BLEだけを先に確認する

1. `app.rb`の`USE_MPU`を一時的に`false`へ変更する。
2. Pico 2 Wへ配置して起動する。
3. serial logで`PRCad`のaddressを記録する。
4. 単一接続hostまたはBLE scannerから接続する。
5. `TX`が約250 ms間隔で増え、2 packet目以降の`delta_mrad`が`1571`に
   なることを確認する。これは約60 rpm相当の生成値である。

期待する起動ログ:

```text
BLE cadence sensor
sensor_role
cadence
mode
fake
UART Peripheral up on: `88:A2:9E:xx:xx:xx`
Advertising started
```

## MPU-6050で確認する

1. 電源を切ってMPU-6050を配線する。
2. `USE_MPU = true`へ戻す。
3. 静止した状態で起動し、`calibrating`中はセンサを動かさない。
4. `mpu_ready`と`Advertising started`を確認する。
5. 接続後、クランクを回して`delta_mrad`、`total_rev`、`flags`の変化を確認する。
6. 1回転の向きや計数が合わなければ、app先頭の`AXIS`と`DIRECTION`を調整する。
7. 静止時の揺れを回転として拾う場合は`GYRO_DEADBAND_DPS`を調整する。

`FLAG_FIRST`、`FLAG_ANGLE_VALID`、`FLAG_ROTATION_CHANGED`、
`FLAG_I2C_ERROR`、`FLAG_SATURATED`、`FLAG_DT_SKIPPED`の意味は
スピードセンサと共通である。連続I2C errorが
`MAX_CONSECUTIVE_I2C_ERRORS`へ達した場合は処理を停止する。

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
| Cadence sensor | speedと同じsensor UF2 | `/home` appだけを`PRCad`用に変える |
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

既存speed sensor appの`DEVICE_NAME = "PRCycle"`と、実機で調整済みのMPU設定を維持する。

## Cadence sensorへのR2P2配置

Sourceと転送先:

```text
r2p2_apps/ble_cycle_cadence_sensor/home/app.rb -> /home/app.mrb
lib/ble_cycle_packet.rb                        -> /lib/ble_cycle_packet.mrb
lib/ble_cycle_sensor/uart_peripheral.rb        -> /lib/ble_cycle_sensor/uart_peripheral.mrb
lib/mpu_6050.rb                                -> /lib/mpu_6050.mrb
lib/mpu_6050/rotation_detector.rb              -> /lib/mpu_6050/rotation_detector.mrb
```

FakeでBLEだけを確認する場合は`USE_MPU = false`、MPU-6050を使う場合は
`USE_MPU = true`にしてから転送時にcompileする。

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
lib/ble_cycle_host/csv_logger.rb                  -> /lib/ble_cycle_host/csv_logger.mrb
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

## CSVログ

Host appは起動時に`/home/logs`を確認し、存在しなければ作成する。ログファイルは
`0000.csv`から始まり、既存の数字だけからなる`*.csv`の最大番号に1を加えた名前を使う。

```text
/home/logs/0000.csv
/home/logs/0001.csv
```

Fileはapp起動時に作成される。Speedまたはcadenceのどちらかがreadyになると記録を開始し、
1秒ごとに、その時点で各estimatorが保持している最新値を書く。250 msごとのsensor packetを
すべて記録するのではない。切断またはtimeoutしたsensorの値は0になる。

```csv
timestamp,speed_kmh,cadence_rpm
2026-07-14 10:00:00 +0900,12.35,89.01
2026-07-14 10:00:01 +0900,12.48,90.22
```

起動時のserial logに、今回作成したpathが出る。

```text
log_file
/home/logs/0000.csv
```

TimestampはPicoRubyの`Time.now.to_s`である。起動前にR2P2 shellの`date`で時刻を確認する。
時計が未設定なら1970年付近などの誤った時刻になるため、Wi-Fiが利用できる場合は`ntpdate`で
時刻を設定してからhost appを起動する。TimezoneはR2P2環境の`TZ`設定に従う。

各rowはLittleFSへ`fsync`する。長時間試験ではCSVが1秒間隔で増えることに加え、BLEの
`reader_gap_count`や表示更新へ悪影響がないことも確認する。書き込みに失敗した場合は
`log_error`をserialへ出してCSV記録だけを停止し、BLE受信とmeter表示は継続する。

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

1. 新sensor UF2 + 既存speed app 1台だけでhostのspeed slotをreadyにする。
2. Cadence appを`USE_MPU = false`にし、cadence slotと約60 rpm表示を確認する。
3. 両sensorを接続し、handleが2個あり、各`interval_ms`が200..350 ms程度か確認する。
4. Cadenceを`USE_MPU = true`へ戻し、静止0 rpm、約1回転/秒で約60 rpmを確認する。
5. Speedだけを再起動し、cadence RXと画面が継続することを確認する。
6. Cadenceだけを再起動し、speed RXと画面が継続することを確認する。
7. Host先行、sensor先行、speed/cadence逆順の各起動順を確認する。
8. `DEBUG_RX = false`、`DEBUG_DISPLAY = false`にして30分、その後可能なら2時間動作させる。
9. `NoMemoryError`、unexpected disconnect、sequence gapを記録する。

実機結果を得るまでは`CADENCE_TODO.md`の段階的検証と長時間検証を完了扱いにしない。

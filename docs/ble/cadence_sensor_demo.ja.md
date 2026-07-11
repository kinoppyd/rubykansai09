# 専用ケイデンスセンサの確認手順

最終更新: 2026-07-11 JST

## 目的

Raspberry Pi Pico 2 WとMPU-6050をクランク側の専用センサとして使い、
独自`BLE::UART` serviceから500 ms周期で回転角を通知する。
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
5. `TX`が約500 ms間隔で増え、2 packet目以降の`delta_mrad`が`3142`に
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

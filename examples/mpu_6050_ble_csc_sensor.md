# Pico 2 W / MPU6050 cadence sensor

`mpu_6050_ble_csc_sensor.rb`は、Raspberry Pi Pico 2 W上のR2P2/PicoRubyで動く
cadence-only CSCP sensorのentry pointです。起動時にMPU-6050またはMPU-6500を確認・校正してからBLEを
開始し、10 ms samplingと1秒measurement notificationを実行します。

WHO_AM_IはMPU-6050の`0x68`とMPU-6500の`0x70`だけを受け付けます。両deviceはこの実装で
使うregister配置、full-scale range、感度係数が共通です。未知の互換品は誤った測定値を防ぐため拒否します。

## 配線と取付

既定値はPico 2 WのI2C1を使います。

| Pico 2 W | MPU6050 | 用途 |
| --- | --- | --- |
| 3V3(OUT) | VCC | 3.3 V電源 |
| GND | GND | Ground |
| GPIO2 | SDA | I2C1 SDA |
| GPIO3 | SCL | I2C1 SCL |

bare MPU6050ではSDA/SCLを3.3 Vへ4.7 kΩ程度でpull-upします。breakout boardにpull-upが
実装済みなら重ねて追加しません。AD0はGNDにしてaddress `0x68`を使います。

基板を右クランクへ剛性を保って固定し、`CRANK_AXIS = :x`がクランク回転軸、
`CRANK_DIRECTION = 1`が正転になる向きにします。取付方向が異なる場合はaxisまたはdirectionを
変更します。走行前に`examples/mpu_6050_rotation_verify.rb`で欠落・二重計数を確認してください。

この構成はwheel speedを提供しません。wheel外周のMPU6050はgyro/accelerometerが高速で
飽和するため、wheel sensorにはHall/reed sensorを推奨します。

## PicoRuby patchとfirmware

最初に`docs/ble/cscp_sensor.ja.md`の手順でPicoRubyとBTstack patchを適用し、標準の
`r2p2:picoruby:pico2_w:prod` firmwareをbuildして書き込みます。patchにはnative CSCS
server、固定長BLE event ring、再利用I2C buffer APIに加え、IRBのcompiler options二重解放を
修正するPicoRuby公式patchのbackportが含まれます。R2P2の`main_task.rb`、`main.c`、USB、
CMakeの起動処理は変更しません。

## Ruby sourceを配置する

`build/cscp_r2p2_app`以下のRuby sourceを、同じpathでR2P2 filesystemへ転送します。

```text
/lib/ble_transport.rb
/lib/ble_transport/picoruby_peripheral.rb
/lib/mpu_6050.rb
/lib/mpu_6050/rotation_detector.rb
/home/app.rb
```

転送後、R2P2 shellから次を実行します。

```sh
load "/home/app.rb"
```

起動時はクランクを約1秒静止させます。校正が完了するまでadvertisingは始まりません。
サイコン側はcadence sensorとしてpair/connectします。wheel circumference設定はこの
cadence-only sensorの値には影響しません。

## メモリと診断

sampling loopはMPU6050の14 byte String、advertising data、native measurement stateを再利用し、
履歴配列やsampleごとの文字列を作りません。cadence-only entry pointは汎用
`BLECSCService`と`MPU6050BLECSC`をloadせず、native CSCS transportへ直接counterを渡します。
配置するbytecodeは7 file、26,100 byteから5 file、20,440 byteへ減少しています。
診断版は`DEBUG_LOG = true`で、状態変化時と5秒ごとに固定labelと数値だけを出力します。
`diagnosis`の意味は次の通りです。

| 値 | 判定 |
| ---: | --- |
| 0 | BLE linkが未接続。pairing情報の保存だけで現在は接続していない |
| 1 | 接続済みだがCSC Measurement CCCDが無効。サイコンがnotificationをsubscribeしていない |
| 2 | notificationは有効だが回転eventが0。axis、direction、取付、gyro値を確認する |
| 3 | 接続、CCCD、回転eventがすべて成立。通知経路は動作中 |

`measurement_status`はbit 0がnative client handle、bit 1がnotification enable、bit 2が
send pendingです。`gyro_min_dps`と`gyro_max_dps`が回転中もほぼ0なら`CRANK_AXIS`が違います。
`rotation_events`だけ増えてサイコン表示が変わらない場合は、`notify_enabled`と
`event_queue_dropped`を確認します。診断終了後は`DEBUG_LOG = false`へ戻すと、sampling loopで
診断用の集計とserial出力を行いません。

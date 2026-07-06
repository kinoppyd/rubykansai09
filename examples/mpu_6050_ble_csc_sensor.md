# Pico 2 W / MPU6050 cadence sensor

`mpu_6050_ble_csc_sensor.rb`は、Raspberry Pi Pico 2 W上のR2P2/PicoRubyで動く
cadence-only CSCP sensorのentry pointです。起動時にMPU6050を確認・校正してからBLEを
開始し、10 ms samplingと1秒measurement notificationを実行します。

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
server、固定長BLE event ring、再利用I2C buffer APIが含まれます。R2P2の`main_task.rb`、
`main.c`、USB、CMakeの起動処理は変更しません。

## `.mrb`を配置する

次のsourceを`mrbc-prism`で個別にcompileし、R2P2 filesystem上でも同じload pathになるよう
配置します。

```text
/lib/ble_transport.mrb
/lib/ble_transport/picoruby_peripheral.mrb
/lib/mpu_6050.mrb
/lib/mpu_6050/rotation_detector.mrb
/home/app.mrb
```

例:

```sh
tmp/picoruby/bin/mrbc-prism -oble_transport.mrb lib/ble_transport.rb
tmp/picoruby/bin/mrbc-prism -oapp.mrb examples/mpu_6050_ble_csc_sensor.rb
```

残り3 sourceも同様にcompileして上記pathへ配置し、Pico 2 Wを再起動します。標準R2P2の
起動処理が`/home/app.mrb`を自動的にloadします。一時的に手動実行する場合は、R2P2 shellで
次を実行します。

```sh
load "/home/app.mrb"
```

起動時はクランクを約1秒静止させます。校正が完了するまでadvertisingは始まりません。
サイコン側はcadence sensorとしてpair/connectします。wheel circumference設定はこの
cadence-only sensorの値には影響しません。

## メモリと診断

sampling loopはMPU6050の14 byte String、advertising data、native measurement stateを再利用し、
履歴配列やsampleごとの文字列を作りません。cadence-only entry pointは汎用
`BLECSCService`と`MPU6050BLECSC`をloadせず、native CSCS transportへ直接counterを渡します。
配置するbytecodeは7 file、26,100 byteから5 file、20,440 byteへ減少しています。
`DEBUG_LOG = false`ではloop中にserial出力しません。
一時的に`true`へ変更すると60秒ごとに、crank count、最大loop時間、overrun、I2C error、
BLE event dropを固定labelと数値だけで出力します。

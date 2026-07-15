# BLEサイクルホストのGC9A01 2画面構成

Pico 2 W 1台でBLEホストと2台のGC9A01を動かし、1台目へ速度、2台目へ
ケイデンスを表示する構成です。`picoruby-gc9a01-speedometer`の2画面対応を
含み、BLE central connectionを2本持つUF2が必要です。

## 配線

速度画面はSPI0を使います。

| 速度GC9A01 | Pico 2 W GPIO |
| --- | ---: |
| SCL / CLK | GP18 |
| SDA / DIN | GP19 |
| CS | GP17 |
| DC | GP20 |
| RST | GP21 |
| BL | GP22 |

ケイデンス画面はSPI1を使います。

| ケイデンスGC9A01 | Pico 2 W GPIO |
| --- | ---: |
| SCL / CLK | GP10 |
| SDA / DIN | GP11 |
| CS | GP9 |
| DC | GP12 |
| RST | GP13 |
| BL | GP14 |

両方のGNDをPico 2 Wと共通にします。VCCとBLについては、2台分の消費電流を
モジュール仕様と電源容量の範囲に収めてください。

## R2P2 app

`r2p2_apps/ble_cycle_host/home/app.rb`は次のモードを使用します。

```ruby
DISPLAY_MODE = :dual_gc9a01
```

Host app先頭でspeed/cadence sensorを設定します。Cadence sensorの実アドレスを
確認するまでは`nil`のまま`PRCad` name fallbackを使用できます。

```ruby
SPEED_DEVICE_ADDRESS = "88:A2:9E:0B:A7:DE"
CADENCE_DEVICE_ADDRESS = nil # 確認後にPRCadのaddressへ置き換える
```

R2P2へ再配置するRubyファイルは次のとおりです。

```text
/home/app.mrb
/lib/ble_cycle_packet.mrb
/lib/ble_cycle_host/advertising_report.mrb
/lib/ble_cycle_host/notification_event.mrb
/lib/ble_cycle_host/multi_uart_transport.mrb
/lib/ble_cycle_host/multi_uart_central.mrb
/lib/ble_cycle_host/display_output.mrb
/lib/ble_cycle_host/speed_estimator.mrb
/lib/ble_cycle_host/cadence_estimator.mrb
```

起動するとBLE接続前に両方の画面が0を表示し、速度を80 km/h、ケイデンスを
120 rpmまで一度スイープして0へ戻します。その後、missing sensorのBLE scanを
開始します。

```text
display_link
dual_gc9a01
display_startup_sweep
start
display_startup_sweep
done
```

Speed packetは`SpeedEstimator`だけへ、cadence packetは`CadenceEstimator`だけへ
渡します。速度画面には`speed_kmh`、ケイデンス画面には`cadence_rpm`を渡します。
片方が切断またはtimeoutした場合はその値だけ0へ戻し、もう片方の接続と表示更新を
維持します。

ケイデンス画面の6時方向にはBLE接続インジケーターを表示します。ストップウォッチは
スピードセンサ、クランクはケイデンスセンサに対応します。各アイコンは未接続時に赤、
該当するBLEスロットが`ready`になると緑へ変わり、切断時は赤へ戻ります。

Host firmwareへ次のpatchを順に含めます。Sensor firmwareは2接続patchを使わず、
BTstack slot数1を維持します。

```text
patches/picoruby-ble-passive-scan.patch
patches/picoruby-ble-notification-listeners.patch
patches/picoruby-ble-central-event-delivery.patch
patches/picoruby-ble-two-connections.patch
patches/picoruby-gc9a01-speedometer.patch
```

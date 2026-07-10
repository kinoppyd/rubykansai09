# BLEサイクルホストのGC9A01 2画面構成

Pico 2 W 1台でBLEホストと2台のGC9A01を動かし、1台目へ速度、2台目へ
ケイデンスを表示する構成です。`picoruby-gc9a01-speedometer`の2画面対応を
含むUF2が必要です。

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

R2P2へ再配置するRubyファイルは次の2つです。

```text
/home/app.mrb
/lib/ble_cycle_host/display_output.mrb
```

起動すると両方の画面が0を表示し、速度は0から80 km/h、ケイデンスは0から
180 rpmまで一度スイープして0へ戻ります。その後BLE scanを開始します。

```text
display_link
dual_gc9a01
display_startup_sweep
start
display_startup_sweep
done
```

BLE frame受信後、速度画面には`estimator.speed_kmh`、ケイデンス画面の針には
`estimator.cadence_rpm`を渡します。現段階では両方とも同じ回転センサから算出した
値です。専用ケイデンスセンサを追加するときは、後者の入力元を切り替えます。

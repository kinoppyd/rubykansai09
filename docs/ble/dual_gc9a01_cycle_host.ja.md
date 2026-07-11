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

R2P2へ再配置するRubyファイルは次の3つです。

```text
/home/app.mrb
/lib/ble_cycle_host/display_output.mrb
/lib/ble_cycle_host/speed_estimator.mrb
```

起動すると両方の画面が0を表示し、速度だけを0から80 km/hまで一度スイープして
0へ戻します。専用センサが未接続のため、ケイデンス針は起動中も0のままです。
その後BLE scanを開始します。

```text
display_link
dual_gc9a01
display_startup_sweep
start
display_startup_sweep
done
```

BLE frame受信後、速度画面には`estimator.speed_kmh`を渡します。ホイール回転数を
ケイデンスとして扱わず、専用ケイデンスセンサを追加するまではケイデンス画面の針へ
常に`0.0`を渡します。専用センサを追加するときは、速度センサとは独立した入力値へ
置き換えます。

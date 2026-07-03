# picoruby-gc9a01-speedometer

R2P2上のPicoRubyからLovyanGFXを使う、240x240 GC9A01速度計です。
Toyota 86の中央メーターを参考に、アナログ針とデジタル速度を同時表示します。

```ruby
require 'gc9a01_speedometer'

GC9A01Display.configure(0, 18, 19, 17, 20, 21, 22, 40_000_000)
meter = GC9A01Speedometer.new
meter.render(28.4, 92)

# 内蔵デモ。速度とケイデンスを往復させる。
meter.demo
```

`configure`の引数は、SPI controller、SCLK、MOSI、CS、DC、RST、BL、SPI
write frequencyの順です。省略した場合は上記と同じ既定値を使用します。LCDを
初期化する`new`や`brightness=`より前に一度だけ呼び出してください。

RP2040のFemtoRubyでも同じオブジェクトAPIを使用します。

センサ取得ループへ組み込む場合は、ブロックする `demo` ではなく `render` を
呼びます。

```ruby
meter = GC9A01Speedometer.new

loop do
  speed_kmh = read_speed
  cadence_rpm = read_cadence
  meter.render(speed_kmh, cadence_rpm)
  Machine.delay_ms(33)
end
```

右下の赤いデジタル表示は`speed_kmh`、アナログ針は`cadence_rpm`を示します。
ケイデンス目盛りは0から180 rpmで、140 rpm以上がレッドゾーンです。

単体のアナログ速度計は、別クラスとして利用できます。

```ruby
meter = GC9A01SimpleSpeedometer.new
meter.render(32.5)
```

この速度計は5時の0 km/hから1時の80 km/hまでを使います。背景は黒、目盛りと
数字は白、針は赤で、デジタル表示とレッドゾーンはありません。

ランダムな目標速度へ滑らかに追従する実走行風デモは、
`examples/gc9a01_speedometer/r2p2_realistic_speedometer_demo.rb`にあります。
デモのSPIピン、輝度、フレーム間隔は同じディレクトリの
`gc9a01_demo_config.rb`へ集約しています。

フレームバッファは使用しません。初回に盤面を直接描画し、以降は古い針の形
だけを消して、交差する目盛りと文字を復元します。mrbgemはfirmwareへ組み込み
済みです。RP2040のFemtoRubyでは`require 'gc9a01_speedometer'`が必要です。
Pico 2のPicoRubyでは明示的な`require`を省略できます。

配線、R2P2への組み込み、UF2のビルド手順は
[`docs/picoruby/gc9a01_speedometer.md`](../../docs/picoruby/gc9a01_speedometer.md)
を参照してください。

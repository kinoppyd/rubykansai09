# R2P2 GC9A01速度計

`picoruby-gc9a01-speedometer`は、R2P2上のRubyからLovyanGFXによる
240x240 GC9A01速度計を操作するネイティブmrbgemです。画面全体の描画はC++で
行い、Rubyからは速度値だけを渡します。

## 対象

- Raspberry Pi Pico (RP2040、FemtoRuby VM)
- Raspberry Pi Pico 2 / Pico 2 W (RP2350、PicoRuby VM)
- R2P2 PicoRuby firmware (`bc559024`)
- GC9A01、240x240円形LCD
- LovyanGFX 1.2.21

RP2040ではRAM容量の制約からPicoRuby VMのR2P2 buildは提供されていません。
代わりにmruby/cベースのFemtoRuby VMを使用します。表示処理本体とRuby APIは
RP2040とRP2350で共通です。

## 配線

標準設定は次の通りです。

| GC9A01 | Pico 2 GPIO | 備考 |
| --- | ---: | --- |
| VCC | 3V3 | モジュールの電圧仕様を確認すること |
| GND | GND | |
| SCL / CLK | GP18 | SPI0 SCLK |
| SDA / DIN | GP19 | SPI0 MOSI |
| CS | GP17 | Chip select |
| DC | GP20 | Data/command |
| RST | GP21 | Reset |
| BL | GP22 | Backlight PWM |

MISOは使用しません。

### 2台を独立表示する場合

1台目は上記SPI0配線を維持し、2台目をSPI1へ接続します。

| 2台目GC9A01 | Pico 2 GPIO | 備考 |
| --- | ---: | --- |
| VCC | 3V3 | 2台分の電源・バックライト電流を確認すること |
| GND | GND | 1台目と共通GND |
| SCL / CLK | GP10 | SPI1 SCLK |
| SDA / DIN | GP11 | SPI1 MOSI |
| CS | GP9 | Chip select |
| DC | GP12 | Data/command |
| RST | GP13 | Reset |
| BL | GP14 | Backlight PWM |

2台目は`configure_secondary`で設定し、meter生成時に表示番号を渡します。

```ruby
GC9A01Display.configure(0, 18, 19, 17, 20, 21, 22, 40_000_000)
GC9A01Display.configure_secondary(1, 10, 11, 9, 12, 13, 14, 40_000_000)

speed_meter = GC9A01SimpleSpeedometer.new(GC9A01Display::PRIMARY)
cadence_meter = GC9A01Speedometer.new(GC9A01Display::SECONDARY)

speed_meter.render(32.5)
cadence_meter.render(32.5, 90)
```

同じSPI controllerを2つのLovyanGFX bus objectで共有する構成は、この実装の
検証対象外です。独立表示ではSPI0とSPI1を分けてください。

## PicoRubyへの組み込み

リポジトリrootにPicoRubyとLovyanGFXを用意します。

```sh
git clone --recursive https://github.com/picoruby/picoruby.git tmp/picoruby
git -C tmp/picoruby checkout bc559024
git clone --branch 1.2.21 --depth 1 \
  https://github.com/lovyan03/LovyanGFX.git tmp/LovyanGFX
```

このパッチとUF2は`bc559024`で検証しています。タグ`3.4.5`はR2P2のCMake
構成が異なるため、このパッチの対象外です。

mrbgemをPicoRubyのtreeから参照できるようにします。

```sh
ln -s ../../../mrbgems/picoruby-gc9a01-speedometer \
  tmp/picoruby/mrbgems/picoruby-gc9a01-speedometer
```

R2P2のbuild設定へパッチを適用します。

```sh
git -C tmp/picoruby apply \
  ../../patches/picoruby-gc9a01-speedometer.patch
```

## UF2をビルドする

Pico 2 Wの場合:

```sh
cd tmp/picoruby
PATH="$HOME/.local/share/mise/installs/ruby/3.4.3/bin:$PATH" \
  ruby -S rake r2p2:picoruby:pico2_w:prod
```

Pico 2の場合はtargetを`pico2`へ変更します。

```sh
ruby -S rake r2p2:picoruby:pico2:prod
```

RP2040のRaspberry Pi Picoの場合はFemtoRuby targetを使用します。

```sh
ruby -S rake r2p2:femtoruby:pico:prod
```

今回生成したUF2は次の場所にあります。

```text
tmp/picoruby/build/r2p2/picoruby/pico2/prod/R2P2-PICORUBY-4.0.0-PICO2-20260703-bc559024.uf2
tmp/picoruby/build/r2p2/picoruby/pico2_w/prod/R2P2-PICORUBY-4.0.0-PICO2_W-20260703-bc559024.uf2
tmp/picoruby/build/r2p2/femtoruby/pico/prod/R2P2-FEMTORUBY-4.0.0-PICO-20260703-bc559024.uf2
```

## RubyからSPI配線を設定する

LCDを初期化する前に、次の8個の整数を指定します。

```ruby
spi_host = 0
sclk = 18
mosi = 19
cs = 17
dc = 20
rst = 21
bl = 22
spi_frequency = 40_000_000

GC9A01Display.configure(
  spi_host, sclk, mosi, cs, dc, rst, bl, spi_frequency
)

meter = GC9A01SimpleSpeedometer.new
```

引数の順序は、SPI controller (`0`または`1`)、SCLK、MOSI、CS、DC、RST、
BL、SPI write frequencyです。CS、RST、BLは`-1`で無効化できます。
SCLK、MOSI、DCは必須です。SPI周波数には1 MHzから100 MHzを指定できますが、
GC9A01では40 MHzを既定値とし、不安定な場合は20 MHzへ下げてください。

`configure`は`new`または`brightness=`より前に呼び出してください。LCD初期化後
に再設定すると`RuntimeError`になります。呼び出さなければ上記の値がそのまま
既定値として使われます。設定値は初期化時にC++へコピーされるため、描画中の
Ruby呼び出しや追加のSPI処理は発生しません。

### デモ共通設定

タコメーターとスピードメーターのデモは、次の共通設定を使用します。

```text
examples/gc9a01_speedometer/gc9a01_demo_config.rb
```

SPI controller、GPIO、SPI周波数、輝度、描画間隔、起動時のスイープ設定はこの
ファイルだけで変更してください。各デモは`GC9A01DemoConfig.apply`を呼び出し、
個別に定数を持ちません。R2P2へ転送するときは、この`.rb`も転送対象に含め、
転送ツールでコンパイルした`/lib/gc9a01_demo_config.mrb`として配置します。

ビルド時の既定値自体を変更する場合は、CMake cache変数も利用できます。

```sh
cmake -S mrbgems/picoruby-r2p2/cmake \
  -B build/r2p2/picoruby/pico2_w/prod \
  -DGC9A01_PIN_CS=13 \
  -DGC9A01_PIN_DC=14 \
  -DGC9A01_PIN_RST=15 \
  -DGC9A01_PIN_BL=16
cmake --build build/r2p2/picoruby/pico2_w/prod
```

変更可能な変数は`GC9A01_SPI_PORT`、`GC9A01_PIN_SCLK`、
`GC9A01_PIN_MOSI`、`GC9A01_PIN_CS`、`GC9A01_PIN_DC`、
`GC9A01_PIN_RST`、`GC9A01_PIN_BL`、`GC9A01_SPI_FREQUENCY`です。
2台目は同名の`GC9A01_SECONDARY_*`変数で設定できます。

## Rubyから実行する

生成したUF2を書き込んだ後、
`examples/gc9a01_speedometer/r2p2_demo.rb`をR2P2上で実行します。

デモでは共通設定ファイルが組み込みmrbgemを読み込み、SPI設定を適用します。

```ruby
require 'gc9a01_demo_config'

GC9A01DemoConfig.apply
meter = GC9A01Speedometer.new
meter.brightness = GC9A01DemoConfig::BRIGHTNESS
meter.demo(GC9A01DemoConfig::FRAME_MS)
```

実際のセンサ値を表示する場合は、ブロックする`demo`ではなく`render`を
呼び出します。

```ruby
meter = GC9A01Speedometer.new

loop do
  speed_kmh = read_speed
  cadence_rpm = read_cadence
  meter.render(speed_kmh, cadence_rpm)
  Machine.delay_ms(33)
end
```

`render(speed_kmh, cadence_rpm)`は、右下へ速度を赤いデジタル文字で表示し、
アナログ針でケイデンスを表示します。ケイデンスは0から180 rpmへclampされ、
140 rpm以上がレッドゾーンです。速度表示は0から999 km/hへclampされます。

`r2p2_demo.rb`は起動時にデジタル速度を0 km/hへ固定したまま、アナログ針を
0から180 rpm、180から0 rpmへ一度素早く動かしてから内蔵デモを開始します。

## 単体アナログ速度計

`GC9A01SimpleSpeedometer`は複合タコメーターとは独立した速度計です。

```ruby
meter = GC9A01SimpleSpeedometer.new
meter.render(32.5)
```

- 入力: 0から80 km/h
- 角度: 時計の5時から時計回りに1時まで
- 背景: 黒
- 数字と目盛り: 白
- 針: 赤
- デジタル表示、レッドゾーン: なし

内蔵デモは`examples/gc9a01_speedometer/r2p2_simple_speedometer_demo.rb`で
実行できます。

実走行に近い不規則な動きは、次のスクリプトで確認できます。

```text
examples/gc9a01_speedometer/r2p2_realistic_speedometer_demo.rb
```

このデモは3秒から7秒ごとに次の目標速度を選び、加速と減速の上限を分けて
滑らかに追従します。通常走行では近い速度へ上下し、低確率で停止または高速域を
選択します。最大目標速度は75 km/hなので、針が毎回80 km/hまで往復することは
ありません。起動時のみ表示確認として、針を0から80 km/h、80から0 km/hへ
一度素早く動かしてからランダム走行を開始します。

## メモリ構成

フレームバッファは使用しません。初回は盤面全体をLCDへ直接描画します。以降は
古い針と影の形だけを盤面色で消し、その範囲と交差する目盛り・文字・速度表示を
復元してから新しい針を描きます。Ruby heapは通常値のまま、Pico 2では444 KiB、
Pico 2 Wでは364 KiBです。RP2040では184 KiBのFemtoRuby heapを使用します。

このmrbgemはfirmwareへ組み込み済みです。Pico 2のPicoRubyでは
アプリケーション側の`require`は不要です。RP2040のFemtoRubyでは組み込みgemの
初期化とRuby wrapperの読み込みのために`require 'gc9a01_speedometer'`を実行します。

## RP2040 / FemtoRuby

RP2040でもRP2350と同じ`configure`、`new`、`render` APIを使用します。
FemtoRubyでは、Rubyの`initialize`からネイティブの`_init`を呼び出すことで、
mruby/cの通常のオブジェクト生成処理を維持したままLCDを初期化します。

`new`で処理が止まる場合は、最初にRubyへ指定したSPI controllerとGPIOが実際の
配線に一致しているか確認してください。RP2040で使用可能な組み合わせは次の通り
です。

- SPI0 SCLK: GP2、GP6、GP18、GP22
- SPI0 MOSI: GP3、GP7、GP19、GP23
- SPI1 SCLK: GP10、GP14、GP26
- SPI1 MOSI: GP11、GP15、GP27

SCLKとMOSIは同じSPI controllerの組み合わせを指定します。CS、DC、RST、BLも
GPIO番号と物理pin番号を取り違えないようにしてください。

## IRB入力中に停止する場合

初期実装は57,600 byteの全画面バッファを確保するため、Pico 2 WのRuby heapを
364 KiBから304 KiBへ縮小していました。この構成では、IRBが入力中に行う構文
解析でメモリの余裕がなくなり、`require`などの式を入力した時点で応答しなく
なる場合があります。

修正版はフレームバッファを使わず、Ruby heapを通常の364 KiBへ戻しています。
`r2p2_demo.rb`の先頭に`require`は必要ありません。旧UF2を使用している場合は、
2026-07-03に再生成したUF2を書き込み直してください。

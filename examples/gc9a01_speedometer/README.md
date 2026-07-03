# GC9A01 speedometer demo

LovyanGFXとPico SDKを使い、240x240 GC9A01円形LCDへ車の速度計を描画する
デモです。0から240 km/hまで約9秒周期で往復し、針を30 fpsで更新します。

描画は240x240 RGB565スプライト1枚へ合成してからLCDへ一括転送します。
スプライトの使用量は約112.5 KiBです。デフォルトターゲットはRaspberry Pi
Pico 2です。

## 配線

| GC9A01 | Pico 2 GPIO | 備考 |
| --- | ---: | --- |
| VCC | 3V3 | モジュールの仕様を確認すること |
| GND | GND |  |
| SCL / CLK | 18 | SPI0 SCK |
| SDA / DIN | 19 | SPI0 TX / MOSI |
| CS | 17 |  |
| DC | 20 |  |
| RST | 21 |  |
| BL | 22 | PWMバックライト |

LCDモジュール側の表記が `SDA` でも、この接続ではI2CではなくSPIのMOSIです。

## 依存関係

- Pico SDK 2.x
- LovyanGFX 1.2.21
- CMake 3.13以上
- Arm GNU Toolchain

このリポジトリのルートでLovyanGFXを取得します。

```sh
git clone --depth 1 --branch 1.2.21 \
  https://github.com/lovyan03/LovyanGFX.git tmp/LovyanGFX
```

## Pico 2向けビルド

既存のPicoRuby checkout内のPico SDKを使う場合:

```sh
export PICO_SDK_PATH="$PWD/tmp/picoruby/mrbgems/picoruby-r2p2/lib/pico-sdk"
cmake -S examples/gc9a01_speedometer \
  -B tmp/build-gc9a01-speedometer \
  -DPICO_BOARD=pico2 \
  -DLOVYANGFX_PATH="$PWD/tmp/LovyanGFX"
cmake --build tmp/build-gc9a01-speedometer -j
```

生成物:

```text
tmp/build-gc9a01-speedometer/gc9a01_speedometer.uf2
```

Pico 2 Wでは `-DPICO_BOARD=pico2_w`、RP2040 Picoでは
`-DPICO_BOARD=pico` を指定します。RP2040はRAMが少ないため、他の機能を同時に
組み込む場合は16-bitフル画面スプライトを見直してください。

## ピンやSPI速度を変更する

CMake configure時に値を上書きできます。

```sh
cmake -S examples/gc9a01_speedometer \
  -B tmp/build-gc9a01-speedometer \
  -DPICO_BOARD=pico2 \
  -DGC9A01_PIN_CS=13 \
  -DGC9A01_PIN_DC=14 \
  -DGC9A01_PIN_RST=15 \
  -DGC9A01_PIN_BL=16 \
  -DGC9A01_PIN_SCLK=10 \
  -DGC9A01_PIN_MOSI=11 \
  -DGC9A01_SPI_PORT=1 \
  -DGC9A01_SPI_FREQUENCY=40000000
```

表示が白黒反転する場合は `lgfx_gc9a01.hpp` の `config.invert`、赤と青が
入れ替わる場合は `config.rgb_order` を変更します。描画が不安定な場合は
`GC9A01_SPI_FREQUENCY` を20 MHzへ下げて確認してください。

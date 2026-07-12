# picoruby-gc9a01-speedometer.patch

対象パッチ: [`patches/picoruby-gc9a01-speedometer.patch`](../../patches/picoruby-gc9a01-speedometer.patch)

## パッチの概要

`picoruby-gc9a01-speedometer` native mrbgemとLovyanGFXをR2P2 firmwareへ組み込み、
Raspberry Pi Pico/Pico 2/Pico 2 WからGC9A01円形LCDを駆動できるようにするbuild patchである。

変更対象は次の4ファイルである。

| ファイル | 変更内容 |
| --- | --- |
| `build_config/r2p2-femtoruby-pico.rb` | RP2040/FemtoRubyへmrbgemを追加 |
| `build_config/r2p2-picoruby-pico2.rb` | Pico 2/PicoRubyへmrbgemを追加 |
| `build_config/r2p2-picoruby-pico2_w.rb` | Pico 2 W/PicoRubyへmrbgemを追加 |
| `mrbgems/picoruby-r2p2/cmake/CMakeLists.txt` | C++ source、LovyanGFX、pin設定、linkを追加 |

本パッチ自体にdisplay driver本体は含まれない。Driverはこのリポジトリの
`mrbgems/picoruby-gc9a01-speedometer`、描画/SPI基盤は外部LovyanGFX checkoutから供給する。

## 必要な理由

R2P2の`/home`や`/lib`へ配置できるRuby bytecodeだけでは、LovyanGFXを使うC++ display
driverを後から追加できない。Native mrbgemはUF2 build時にcompile/linkする必要がある。

元のR2P2 CMake設定には次が不足している。

- `picoruby-gc9a01-speedometer`をbuild対象gemへ加える設定
- mrbgemの`ports/rp2040/*.cpp`をsourceとして収集する処理
- 外部LovyanGFX CMake projectの追加
- Firmware targetからLovyanGFXへのlink
- GC9A01のSPI controller、GPIO、周波数をC++へ渡すcompile definition
- 2台目GC9A01用の独立したSPI/pin設定

これらをbuild layerへ追加し、Ruby appは小さな数値だけをnative rendererへ渡す構成にする。
Full framebufferをRuby heapへ持たず、BLE hostと2画面表示を同じPico 2 Wへ収めるためにも
native実装が必要である。

## 詳細な技術的解説

### Build configへのmrbgem追加

3種類のR2P2 build configへ次を追加する。

```ruby
conf.gem core: 'picoruby-gc9a01-speedometer'
```

対象はRP2040のFemtoRuby build、RP2350のPicoRuby Pico 2 build、Pico 2 W buildである。
Pico 2 W構成では既存BLE mrbgemと同時にlinkされるため、cycle hostがBLE受信とLCD描画を
1台で実行できる。

### LovyanGFXの検出

CMakeは既定で次のpathをLovyanGFX checkoutとして使う。

```text
${PICORUBY_ROOT}/../LovyanGFX
```

`LOVYANGFX_PATH`はCMake cache variableなので、`-DLOVYANGFX_PATH=...`で変更できる。
PicoRuby tree内にGC9A01 mrbgem directoryが存在する場合だけLovyanGFXを追加する。

```cmake
if(EXISTS "${PICORUBY_ROOT}/mrbgems/picoruby-gc9a01-speedometer")
  add_subdirectory(${LOVYANGFX_PATH} ${CMAKE_BINARY_DIR}/LovyanGFX)
  set(PICORB_HAS_GC9A01_SPEEDOMETER ON)
endif()
```

MrbgemがあるのにLovyanGFXの`CMakeLists.txt`がなければ、曖昧なcompile errorにせず
`FATAL_ERROR`でbuildを停止する。

### C++ sourceの収集

元のR2P2 source globはC fileだけを対象にしている。パッチは`ports/rp2040/*.cpp`と
`ports/common/*.cpp`を追加し、GC9A01 native implementationをC++ compilerへ渡す。

この変更は全mrbgem directoryをglobするため、GC9A01以外の`.cpp`が追加された場合もbuild
対象になる。PicoRuby update時には重複compileや意図しないC++ sourceがないか確認する。

### Primary/secondary display設定

Primary displayの既定値は次のとおり。

| 項目 | 値 |
| --- | ---: |
| SPI controller | `0` |
| SCLK | GP18 |
| MOSI | GP19 |
| CS | GP17 |
| DC | GP20 |
| RST | GP21 |
| BL | GP22 |
| SPI frequency | 40 MHz |

Secondary displayはSPI1、SCLK GP10、MOSI GP11、CS GP9、DC GP12、RST GP13、BL GP14、
40 MHzを既定にする。各値はCMake cache variableから`target_compile_definitions`でC++へ
渡される。

RuntimeではLCD instance生成前にRuby APIの`GC9A01Display.configure`と
`configure_secondary`で上書きできる。初期化後の再設定はできない。

### LovyanGFX link

Mrbgemが検出された場合だけfirmware targetへ`LovyanGFX`をlinkする。GC9A01なしbuildでは
このtargetを追加しないため、display関連code/依存をUF2へ含めずに済む。

```cmake
target_link_libraries(${PROJECT_NAME} PRIVATE LovyanGFX)
```

### 描画とmemory

Native mrbgemは240x240 full framebufferを確保せず、初回に盤面を直接描画し、以降は古い針
周辺だけを消去・復元して新しい針を描く。Ruby側は速度/ケイデンスの数値を渡すだけで、
framebufferをRuby heapへ置かない。

2接続BLE + dual GC9A01最終buildではBSS 444,748 bytes、heap limitまで46,180 bytesの空きを
確認した。これは特定revisionとbuild optionでの値であり、将来のmrbgem追加後も同じ余裕を
保証しない。

## 他に必要な説明事項

### 事前に必要なdirectory

PicoRuby treeから次の2つを参照可能にする。

```text
tmp/picoruby/mrbgems/picoruby-gc9a01-speedometer
tmp/LovyanGFX
```

Mrbgemはこのリポジトリからsymlinkまたはcopyし、LovyanGFXは対応versionをcheckoutする。
Patchだけ適用してもdriver sourceは追加されない。

### BLE patchからの独立性

GC9A01だけを使うfirmwareではBLE patchは不要である。Cycle hostの2画面firmwareでは、BLE
patch chainの後に本patchを適用する。GC9A01なしhostでは本patchとmrbgemを含めないことで、
通信と表示の問題を分離できる。

### Sensor firmwareには適用しない

Speed/cadence sensorはLCDを駆動しないため、sensor build treeに本patchを適用しない。
不要なtext/BSSと外部dependencyを避け、sensor用PicoRuby treeをcleanに保つ。

### SPIと電源の注意

- MISOは使用しない。
- 2画面はSPI0とSPI1へ分ける。同一SPI controllerを2個のLovyanGFX bus objectで共有する構成は
  検証対象外である。
- 2台分のLCD/backlight電流を考慮し、GNDを共通にする。
- 40 MHzで不安定なら20 MHzへ下げる。
- GPIOのSPI function組み合わせが対象Picoで有効か確認する。

### 適用とbuildの確認

最低限、次を確認する。

1. `git apply --check`が成功する。
2. LovyanGFX pathが正しく、CMake configureが成功する。
3. `.cpp`実装がcompileされ、firmwareがlinkする。
4. 起動時sweepが両画面で表示される。
5. Speed/cadenceを別々に更新して表示が混線しない。
6. BLE同居buildでは2接続中も描画が継続する。

R2P2統合buildはPicoRuby
`b0c1c4828b82b267dab9cabf4a372c46c2a1075e`、Pico SDK 2.2.0で確認した。Mrbgem単体の
詳しいRuby APIと配線は[`docs/picoruby/gc9a01_speedometer.md`](../picoruby/gc9a01_speedometer.md)
を参照する。

# RP2350向けR2P2 UF2ビルド手順

この手順は、`tmp/picoruby` にcloneしたPicoRubyから、Raspberry Pi Pico 2
(RP2350) 向けのR2P2 UF2を作成するためのものです。

今回実行したターゲットは次の通りです。

- VM: `picoruby` (mruby VM)
- Board: `pico2` (Raspberry Pi Pico 2 / RP2350)
- Mode: `prod`
- Rake task: `r2p2:picoruby:pico2:prod`

## 前提条件

- `git`
- CRuby 3.4以上
- `cmake` 3.22以上
- `arm-none-eabi-gcc`
- PicoRuby source tree: `tmp/picoruby`

この環境では次のバージョンでビルドしました。

```text
Ruby: 3.4.3 from mise
cmake: 3.28.3
arm-none-eabi-gcc: 14.3.1
pico-sdk: 2.2.0
pico-extras: sdk-2.2.0
```

macOS標準の `/usr/bin/ruby` は古く、PicoRubyのRake task内で失敗します。
`rake` はRuby 3.4以上の `ruby -S rake` として起動してください。

## Pico SDKを準備する

このリポジトリのrootで実行します。

```sh
cd tmp/picoruby
git submodule update --init --recursive
```

R2P2が要求するPico SDKとpico-extrasのtagをcheckoutします。

```sh
cd mrbgems/picoruby-r2p2/lib/pico-sdk
git fetch origin --tags
git checkout 2.2.0
git submodule update --init --recursive
```

```sh
cd ../pico-extras
git fetch origin --tags
git checkout sdk-2.2.0
git submodule update --init --recursive
```

## ビルドする

repository rootに戻ってから実行します。

```sh
cd tmp/picoruby
PATH="$HOME/.local/share/mise/installs/ruby/3.4.3/bin:$PATH" \
  ruby -S rake r2p2:picoruby:pico2:prod
```

初回のCMake configureでは `picotool` が取得・ビルドされます。ネットワークが
使えない環境ではここで失敗するため、事前に取得済みのキャッシュを使うか、
ネットワークを許可して再実行してください。

### 今回必要だったinclude path回避策

このcheckoutでは、R2P2のCMake定義が古い `mruby-compiler2` pathを参照して
おり、実際に必要な `mrc_common.h` は `mruby-compiler-prism/include` に
ありました。そのため、最初のRake taskは次のエラーで停止しました。

```text
fatal error: mrc_common.h: No such file or directory
```

その場合は、同じ `tmp/picoruby` directoryでCMake cacheに正しいinclude path
を追加してから、ビルドを再開します。

```sh
cmake -S mrbgems/picoruby-r2p2/cmake \
  -B build/r2p2/picoruby/pico2/prod \
  -D CMAKE_C_FLAGS="-mcpu=cortex-m33 -mthumb -I$PWD/mrbgems/mruby-compiler-prism/include -I$PWD/mrbgems/mruby-compiler-prism/lib/prism/include"
```

```sh
cmake --build build/r2p2/picoruby/pico2/prod
```

`-mcpu=cortex-m33 -mthumb` はRP2350 ARM buildに必要です。include pathだけで
`CMAKE_C_FLAGS` を上書きすると、CPU指定が落ちて次のようなassembler errorに
なります。

```text
selected processor does not support `mcrr ...' in Thumb mode
```

また、host/POSIX版PicoRubyのビルドで使ったOpenSSL向けの `CFLAGS` /
`LDFLAGS` は、R2P2 firmware buildには渡さないでください。

## 生成物

今回のビルドでは、次のUF2が生成されました。

```text
tmp/picoruby/build/r2p2/picoruby/pico2/prod/R2P2-PICORUBY-4.0.0-PICO2-20260621-bc559024.uf2
```

同じdirectoryに `.elf`, `.bin`, `.uf2.gz`, `.uf2.zip` も生成されます。

## Pico 2へ書き込む

1. Raspberry Pi Pico 2のBOOTSELボタンを押したままUSB接続します。
2. `RPI-RP2` volumeとしてmountされることを確認します。
3. 生成されたUF2をcopyします。

```sh
cp tmp/picoruby/build/r2p2/picoruby/pico2/prod/*.uf2 /Volumes/RPI-RP2/
```

copy後、Pico 2は自動的に再起動してR2P2 firmwareを起動します。

## ほかのRP2350 target

Pico 2 W向けに作る場合は、boardを `pico2_w` にします。

```sh
cd tmp/picoruby
PATH="$HOME/.local/share/mise/installs/ruby/3.4.3/bin:$PATH" \
  ruby -S rake r2p2:picoruby:pico2_w:prod
```

debug buildが必要な場合は、最後のmodeを `debug` にします。

```sh
ruby -S rake r2p2:picoruby:pico2:debug
```

RP2040のPico / Pico Wでは `picoruby` VMのR2P2 buildは提供されていません。
RP2040向けは `femtoruby` VMを使います。

```sh
ruby -S rake r2p2:femtoruby:pico:prod
```

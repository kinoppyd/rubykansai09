# `tmp/` 配下でPicoRubyをビルドする

このプロジェクトでは、外部リポジトリのcloneやビルド作業を `tmp/`
配下で行います。`.gitignore` では既に `tmp/` を無視しているため、
PicoRuby本体、submodule、ビルド成果物はこのプロジェクトのgit管理対象に
なりません。

以下は、macOS上でPOSIX版PicoRubyバイナリ (`bin/picoruby`) をビルドした
手順です。

## 前提条件

- C toolchain (`clang` / `gcc`)
- `git`
- CRuby 3.4以上
- macOSではHomebrewの `openssl@3`

macOS標準のRubyは古い可能性があります。この環境では `/usr/bin/ruby` が
Ruby 2.6で、PicoRubyのビルドスクリプトを実行できませんでした。そのため
`mise` のRuby 3.4.3を使用しました。

## PicoRubyをcloneする

このリポジトリのrootから実行します。

```sh
mkdir -p tmp
git clone https://github.com/picoruby/picoruby.git tmp/picoruby
cd tmp/picoruby
git submodule update --init --recursive
```

最初からsubmodule込みで取得する場合は、次のようにcloneしても構いません。

```sh
git clone --recurse-submodules https://github.com/picoruby/picoruby.git tmp/picoruby
```

## ビルドする

`rake` はsystem Rubyに紐づいた実行ファイルを直接使わず、Ruby 3.4の
インタプリタ経由で起動します。macOSではHomebrew OpenSSLのinclude pathと
library pathも指定します。

```sh
mise exec ruby@3.4.3 -- ruby -S rake \
  LDFLAGS=-L/opt/homebrew/opt/openssl@3/lib \
  CFLAGS=-I/opt/homebrew/opt/openssl@3/include
```

成功すると、次のファイルが作成されます。

```text
tmp/picoruby/bin/picoruby
tmp/picoruby/bin/mrbc-prism
tmp/picoruby/bin/r2p2
```

`bin/*` は `tmp/picoruby/build/host/bin/*` へのsymlinkです。

## 動作確認

```sh
cd tmp/picoruby
./bin/picoruby -e 'puts "Hello World!"'
```

期待する出力:

```text
Hello World!
```

## 実際に遭遇した問題

### `undefined local variable or method '_1'`

単に `rake` を実行すると、`/Library/Ruby` / system Ruby 2.6側のRakeが
起動し、次のエラーになりました。

```text
NameError: undefined local variable or method `_1'
```

PicoRubyのビルドにはCRuby 3.4以上が必要です。次のように実行します。

```sh
mise exec ruby@3.4.3 -- ruby -S rake
```

`ruby -S rake` とすることで、`rake` コマンド自体が古いsystem Rubyに
紐づいていても、Ruby 3.4のプロセス上でRakeを起動できます。

### `ld: library 'ssl' not found`

Ruby 3.4でビルドを進めるとlink stepまでは進みましたが、macOSでは次の
エラーになりました。

```text
ld: library 'ssl' not found
```

HomebrewのOpenSSLはsystem pathにはlinkされないため、明示的にpathを指定します。

```sh
LDFLAGS=-L/opt/homebrew/opt/openssl@3/lib
CFLAGS=-I/opt/homebrew/opt/openssl@3/include
```

Homebrewのinstall先が異なる場合は、次のコマンドで確認します。

```sh
brew --prefix openssl@3
```

## 補足

上記の手順で作成されるのはhost/POSIX版のPicoRubyバイナリです。
RP2040/RP2350向けfirmwareを作る場合は、PicoRuby本体の
`build_config/r2p2-picoruby-pico.rb` のようなcross compilation用build
configと、Pico SDK toolchainを使用します。

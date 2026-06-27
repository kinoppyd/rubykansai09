# Archived TODO

## 2026-06-27 20:21:56 JST

Resolved ST7789 hardware-validation follow-up:

- [x] Identified PicoRuby UTF-8 expansion of `String#<< integer` as the cause
  of corrupted coordinates and RGB565 data.
- [x] Replaced coordinate, fill, character, and text-row byte builders with
  fixed-size strings written through `String#setbyte`.
- [x] Added the Waveshare 1.3inch LCD Module initialization registers.
- [x] Changed the default `MADCTL` value to the Waveshare setting `0x70`.
- [x] Kept the backlight off until initialization and the startup clear finish.
- [x] Changed `write_line` to draw only the new row until scrolling starts.
- [x] Added exact-byte regression tests for coordinate 239 and RGB565 colors.
- [x] Verified the exact bytes with the built PicoRuby host executable.
- [x] Updated the English and Japanese documentation and verification example.

## 2026-06-26 23:49:12 JST

Resolved by:

- Added `lib/st7789_debug_console.rb`
- Added `examples/st7789_debug_console_verify.rb`
- Added `test/st7789_debug_console_test.rb`
- Added `docs/st7789/debug_console.md`
- Added `docs/st7789/debug_console.ja.md`
- Verified host tests with `ruby -Ilib test/st7789_debug_console_test.rb`
- Verified existing tests with `ruby -Ilib test/ble_csc_service_test.rb`
- Verified syntax with `ruby -c lib/st7789_debug_console.rb`
- Verified syntax with `ruby -c examples/st7789_debug_console_verify.rb`
- Verified PicoRuby host smoke with `tmp/picoruby/build/host/bin/picoruby`

Completed TODO items:

- [x] モジュール名と配置を決める。
  - [x] `lib/st7789_debug_console.rb`
  - [x] `ST7789DebugConsole`
- [x] 240x240 RGB565 全画面 framebuffer は使わない方針にする。
  - [x] 240 * 240 * 2 = 115,200 bytes の全画面バッファは持たない。
  - [x] 8x8文字セル単位、または小さいピクセルchunk単位で描画する。
- [x] 最初の機能範囲を「デバッグ用テキストライン出力」に絞る。
  - [x] `write_line(text)` と `puts(text)` を実装。
  - [x] 固定幅ASCIIフォントを実装。
  - [x] foreground/background の2色を扱う。
  - [x] 画面回転、任意フォント、日本語フォント、画像描画は制限事項として文書化。
- [x] LCDモジュールの接続ピンを設定できるようにする。
  - [x] SPI unit、SCK、COPI/MOSI、CS、DC、RST、BL/backlight を example 定数で指定。
  - [x] CIPO/MISO 未接続向けに `cipo_pin: -1` をexampleに記載。
  - [x] 実機固有の最終ピン確定はexample冒頭の定数変更で対応。
- [x] LCDモジュール固有の表示設定を設定できるようにする。
  - [x] 240x240 表示領域。
  - [x] X/Y offset。
  - [x] `MADCTL`。
  - [x] `INVON` / `INVOFF`。
- [x] PicoRuby firmware に必要な `picoruby-spi` と `picoruby-gpio` をexampleで要求する。
- [x] ST7789 command/data 書き込みAPIを設計・実装する。
  - [x] `command(byte)`
  - [x] `data(byte_or_string)`
  - [x] `set_window(x0, y0, x1, y1)`
  - [x] `write_pixels(rgb565_data)`
- [x] GPIO制御をPicoRuby向けに実装する。
  - [x] DC pin の command/data 切り替え。
  - [x] RST pin の reset sequence。
  - [x] BL pin のON/OFF。
- [x] ST7789 初期化シーケンスを実装する。
  - [x] `SWRESET`
  - [x] `SLPOUT`
  - [x] `COLMOD` を RGB565 / 16bit に設定。
  - [x] `MADCTL`
  - [x] `INVON` / `INVOFF`
  - [x] `DISPON`
- [x] `fill_rect(x, y, w, h, color)` を小さいchunkで実装する。
  - [x] 全画面クリアにも使用。
  - [x] 大きなStringを作らず `:chunk_pixels` 単位でRGB565データを生成。
- [x] ASCII固定幅フォントを決める。
  - [x] 5x7 glyph を 8x8 cell として描画。
  - [x] フォントデータは数値テーブルとして同梱。
- [x] 1文字描画を実装する。
  - [x] `draw_char(x, y, ch, fg, bg)`
  - [x] 1文字分のRGB565バッファだけを生成。
- [x] 1行描画を実装する。
  - [x] `draw_text_line(row, text)`
  - [x] 長すぎる文字列は画面幅で切る。
  - [x] 余白は背景色で埋める。
- [x] スクロール方針を決める。
  - [x] 行リングバッファを保持して全行再描画。
  - [x] 240 / 8 = 30 行を標準にした。
  - [x] 行文字列の最大長は `cols` で固定。
- [x] デバッグ出力APIを実装する。
  - [x] `write_line(text)`
  - [x] `clear`
  - [x] `backlight(on)`
  - [x] `color(fg, bg = nil)`
- [x] ST7789単体確認用 example を作る。
  - [x] `examples/st7789_debug_console_verify.rb`
  - [x] 起動時に画面クリア。
  - [x] 複数行のテキストを表示。
  - [x] カウンタを1秒ごとに追記。
- [x] MPU-6050検証コードと接続する方針を決める。
  - [x] 詳細ログはUSB serial、LCDには短い状態行を出す方針として文書化。
  - [x] `EVENT`, `count`, `axis`, `gyro_dps`, `angle`, `dt_skipped` を優先表示候補にした。
- [x] CRuby用のFake SPI/Fake GPIOを用意する。
- [x] ST7789初期化コマンド列をテストする。
- [x] `set_window` の `CASET` / `RASET` / `RAMWR` をテストする。
- [x] `fill_rect` が期待サイズのRGB565データを書き込むことをテストする。
- [x] テキスト行の切り詰め、行送り、リングバッファ再描画をテストする。
- [x] PicoRuby host build で require と最小描画APIのsmoke testを実行する。
- [x] `docs/st7789/debug_console.md` を作成する。
- [x] `docs/st7789/debug_console.ja.md` を作成する。
- [x] 配線例、SPI unit名、初期化オプション、メモリ方針を書く。
- [x] 240x240 LCDで表示できる行数と文字数を書く。
- [x] 既知の制限として、日本語フォントなし、画像描画なし、全画面framebufferなしを明記する。

## 2026-06-14 22:28:44 JST

Resolved by:

- Added `lib/ble_transport.rb`
- Added `lib/ble_csc_service.rb`
- Added `lib/mpu_6050_ble_csc.rb`
- Added `test/ble_csc_service_test.rb`
- Verified PicoRuby BLE API availability from the official `picoruby/picoruby` repository cloned to `/private/tmp/picoruby-inspect`
- Ran `ruby -c` on new libraries
- Ran `ruby -Ilib test/ble_csc_service_test.rb`

Completed TODO items:

- [x] PicoRuby firmware で利用可能な BLE API を確認する。
  - [x] GATT server を作れるか。
  - [x] Advertising data / scan response を設定できるか。
  - [x] Characteristic notification を送れるか。
  - [x] CCCD write を受け取れるか。
  - [x] Write request を扱えるか。
  - [x] Indication は `picoruby-ble` の Ruby API では未公開と判断し、今回の CSCS 実装では使わない方針にした。
- [x] PicoRuby だけで足りない場合の native bridge 方針を決める。
  - [x] CSCS の初期実装では native bridge なし。PicoRuby の `picoruby-ble` を使う。
  - [x] SC Control Point / indication が必要になった場合のみ native bridge を再検討する。
- [x] BLE の最初の互換ターゲットを決める。
  - [x] CSCS combined speed/cadence を主対象にし、speed-only / cadence-only も同じ encoder で扱う。
- [x] `lib/ble_transport.rb` を作る。
- [x] BLE stack の違いを吸収する最小 interface を定義する。
  - [x] `start_advertising(name:, services:, data: nil)`
  - [x] `stop_advertising`
  - [x] `add_service(uuid)`
  - [x] `add_characteristic(service, uuid:, properties:, permissions:, value: nil)`
  - [x] `notify(characteristic, bytes)`
  - [x] `indicate(characteristic, bytes)` は fake で実装し、PicoRuby adapter では unsupported として明示的に例外化した。
  - [x] `on_write(characteristic) { |bytes| ... }`
  - [x] `connected?`
- [x] BLE API が未実装でも host-side test ができる fake transport を用意する。
- [x] byte string 生成を Ruby/PicoRuby の両方で壊れないように扱う。
- [x] Little-endian encoder helper を用意する。
  - [x] `u8`
  - [x] `u16_le`
  - [x] `s16_le`
  - [x] `u32_le`
- [x] `lib/ble_csc_service.rb` を作る。
- [x] GATT service UUID `0x1816` を advertise する。
- [x] CSC Measurement characteristic `0x2A5B` を `Notify` で追加する。
- [x] CSC Feature characteristic `0x2A5C` を `Read` で追加する。
- [x] Sensor Location characteristic `0x2A5D` を必要に応じて追加する。
- [x] SC Control Point characteristic `0x2A55` は後回しにし、必要になったら `Write + Indicate` で追加する方針にした。
- [x] CSC Feature bit を実装する。
  - [x] Wheel Revolution Data Supported
  - [x] Crank Revolution Data Supported
  - [x] Multiple Sensor Locations Supported
- [x] CSC Measurement payload encoder を実装する。
  - [x] speed-only: flags `0x01`, cumulative wheel revolutions, last wheel event time
  - [x] cadence-only: flags `0x02`, cumulative crank revolutions, last crank event time
  - [x] combined: flags `0x03`, wheel pair, crank pair
- [x] `RotationEvent#time_ms` を BLE CSCS event time に変換する。
  - [x] `ticks = (time_ms * 1024 / 1000) % 65536`
  - [x] wheel event time と crank event time を独立管理する
- [x] notification interval を決める。
  - [x] 基本は 1 Hz。
  - [x] 回転イベント発生直後に即時 notify できる API にした。
  - [x] 停止中も同じ counter/event time で周期 notify できる API にした。
- [x] サイコン側が wheel circumference を持つ前提で、BLE では周長を送らない。
- [x] `MPU6050::RotationDetector` と BLE CSCS encoder を接続する module を作る。
  - [x] `lib/mpu_6050_ble_csc.rb`
- [x] wheel detector と crank detector を独立して持てる API にする。
- [x] mounting axis と direction を設定できるようにする。
  - [x] wheel axis
  - [x] wheel direction
  - [x] crank axis
  - [x] crank direction
- [x] false positive を抑える設定を外から渡せるようにする。
  - [x] `alpha`
  - [x] `min_period_ms`
  - [x] `max_period_ms`
  - [x] `gyro_deadband_dps`
- [x] sampling loop の責務を分ける。
  - [x] MPU-6050 sampling
  - [x] rotation detection
  - [x] BLE payload update
  - [x] notification scheduling
- [x] I2C read failure と BLE disconnect を処理する。
  - [x] `MPU6050BLECSC#tick` は例外を `last_error` に保存して `false` を返す。
  - [x] BLE disconnect 状態は transport に閉じ込め、fake/PicoRuby adapter から `connected?` で見られる。
- [x] 接続前も回転 counter を継続するか、接続時に reset するか決める。
  - [x] 接続前も counter は継続する方針にした。
- [x] Battery Service `0x180F` を追加する。
- [x] Battery Level characteristic `0x2A19` を `Read + Notify` で公開する。
- [x] Device Information Service `0x180A` を追加する。
- [x] Manufacturer Name, Model Number, Firmware Revision を公開する。
- [x] CSC Measurement の payload を byte-level で確認する。
- [x] Public API proposal を実装する。
  - [x] `MPU6050BLECSC.new(...)`
  - [x] `sensor.start`
  - [x] `sensor.tick`
  - [x] `sensor.run`

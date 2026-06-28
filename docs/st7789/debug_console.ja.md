# ST7789 Debug Console

`ST7789DebugConsole` は、ST7789 コントローラを搭載した Waveshare
1.3inch 240x240 LCD Module 向けの、PicoRuby用テキストコンソールです。

MPU-6050 を使った自転車センサ開発中のデバッグ出力を想定しています。実装では、240x240 の RGB565 全画面 framebuffer を意図的に使いません。

## メモリ方針

RGB565 の全画面 framebuffer を持つと、次のメモリが必要です。

```text
240 * 240 * 2 = 115,200 bytes
```

これは PicoRuby の組み込み用途では重すぎます。そのため、このコンソールは小さなピクセル塊を直接 LCD に書き込みます。

- `fill_rect` はCSを有効に保ち、再利用するRGB565 chunkを連続送信する。
- `draw_char` は、8x8 文字セル1つ分、128 bytes だけを生成する。
- 5x7フォントは480個のIntegerを持つArrayではなく、480 bytesのString
  1個として保持する。
- テキスト出力は、短い行文字列のリングバッファだけを持つ。
- `draw_text_line` は小さな1bitマスクへ文字を描画する。1倍では240 bytes、
  2倍では480 bytesを使用する。
- RGB565画素は最大64 bytes単位で送信し、3,840 bytesの行バッファを
  常駐させず、SPI層でも確保しない。
- 標準の`:page`モードは、最初の物理行へ戻る前に前ページを消去する。

240x240 LCD を 8x8 セルで使う場合、標準では次の表示になります。

- 30 columns
- 30 rows
- ASCII のみ

## 配線

モジュールには SPI オブジェクトと、制御用 GPIO オブジェクトを渡します。

```ruby
spi = SPI.new(
  unit: :RP2040_SPI0,
  frequency: 24_000_000,
  sck_pin: 18,
  cipo_pin: -1,
  copi_pin: 19,
  cs_pin: 17,
  mode: 0
)

dc = GPIO.new(20, GPIO::OUT)
rst = GPIO.new(21, GPIO::OUT)
bl = GPIO.new(22, GPIO::OUT)

lcd = ST7789DebugConsole.new(spi, dc, rst, bl)
```

SPI unit は、配線したピンに応じて `:RP2040_SPI0` または `:RP2040_SPI1` を使います。PicoRuby の RP2040/RP2350 ターゲットでは、unit 名は `RP2040_SPI*` 形式のままです。

LCD モジュールに MISO/CIPO がない場合は、`cipo_pin: -1` を指定します。

## 表示オプション

コンストラクタの5番目の引数にオプションハッシュを渡せます。

```ruby
lcd = ST7789DebugConsole.new(
  spi,
  dc,
  rst,
  bl,
  :width => 240,
  :height => 240,
  :x_offset => 0,
  :y_offset => 0,
  :madctl => 0x70,
  :invert => true,
  :scroll_mode => :page,
  :text_scale => 2,
  :foreground => ST7789DebugConsole::GREEN,
  :background => ST7789DebugConsole::BLACK,
  :chunk_pixels => 127
)
```

主なオプション:

- `:x_offset`, `:y_offset`: LCDモジュール固有のRAMオフセット。
- `:madctl`: 画面回転やRGB/BGR順を決める ST7789 の Memory Access Control 値。
- `:invert`: true なら `INVON`、false なら `INVOFF` を送る。
- `:foreground`, `:background`: RGB565 の文字色と背景色。
- `:scroll_mode`: `:page`はページ境界で画面を消去し、`:wrap`は1物理行を
  上書きし、`:redraw`は全行を再描画して通常のスクロール表示を行う。
- `:text_scale`: 整数の文字倍率。8x8セルには`1`、16x16セルには`2`を使う。
- `:chunk_pixels`: 1回の塗りつぶし転送に含めるピクセル数。RGB565転送が
  PicoRuby SPIの256 bytesヒープ境界を超えないよう、`1..127`に制限する。
- `:auto_init`: テストや独自初期化時に false にできる。
- `:clear_on_init`: 起動時に画面クリアしたくない場合は false にする。

標準値は Waveshare 1.3inch LCD Module に合わせています。

- `:madctl => 0x70`
- `:x_offset => 0`
- `:y_offset => 0`
- `:invert => true`
- `:scroll_mode => :page`
- `:text_scale => 1`

初期化では、Waveshare公式ドライバの porch、gate、VCOM、frame rate、
power、gamma設定を送信します。バックライトは初期化と起動時クリアが
終わるまで消灯します。

## 描画と行あふれ

1倍では高さ8ピクセルの1行が3,840 bytes、2倍では高さ16ピクセルの1行が
7,680 bytesのRGB565データになります。ドライバはLCDの描画領域を設定する
前に、小さな1bitマスク上で文字列全体を完成させます。その後、再利用する
4種類のRGB565パターンを使って2ピクセルずつ展開します。各`SPI#write`は
最大64 bytesであり、PicoRuby SPIの256 bytesスタックバッファ境界を
下回るため、SPI層はヒープバッファを確保しません。

これは以前の3,840 bytes常駐行バッファを置き換えるものです。以前は
`SPI#write`も同じサイズの一時領域へコピーしていたため、MPU-6050やBLE
オブジェクトが存在するR2P2のヒープでは、即座に`NoMemoryError`が発生
する可能性がありました。

## 文字サイズ

大きなデバッグ文字には`:text_scale => 2`を指定します。5x7フォントの
画素と周囲の8x8セルを、縦横とも2倍に拡大します。

| 倍率 | セル | 列数 | 行数 | マスクメモリ |
| --- | --- | ---: | ---: | ---: |
| `1` | 8x8 | 30 | 30 | 240 bytes |
| `2` | 16x16 | 15 | 15 | 480 bytes |

`examples/st7789_debug_console_verify.rb`は2倍表示を使用します。互換性と
最小メモリを維持するため、ライブラリの標準値は1倍のままです。

標準の`:scroll_mode => :page`は組み込みデバッグ出力向けです。最終行の
次では、保持している各行の文字描画矩形と行文字列だけを消去してから、
次の行を物理行0へ描画します。変更のない背景を転送し直さないため、
115,200 bytesの全画面クリアより高速です。

ページ切り替え時の待ち時間を最小にする必要がある場合だけ、
`:scroll_mode => :wrap`を指定します。このモードは他の行を消去せずに
物理行を循環上書きするため、置き換わっていない古い行が表示に残ります。

端末のような通常のスクロール表示が必要な場合は、
`:scroll_mode => :redraw`を指定します。行描画自体は以前より高速ですが、
画面が埋まった後は、新しい行ごとに表示中の全行、合計115,200 bytesを
生成して転送する必要があります。

Waveshare標準の`MADCTL=0x70`では、ST7789のハードウェア縦スクロールを
使用していません。この値では`MV`ビットが有効ですが、
[ST7789Vデータシート](https://www.lcd-module.com/fileadmin/eng/pdf/zubehoer/ST7789V.pdf)は、
縦スクロール中のフレームメモリ書き込みに`MV=0`を要求します。

## PicoRubyのバイナリ文字列

PicoRubyでは、`String.new << integer` に 0x80 以上の整数を追加すると、
1バイトではなくUTF-8の複数バイトになります。RGB565データには正確な
バイト列が必要なため、このドライバでは固定長Stringを作り、
`String#setbyte` で各バイトを書き込みます。

この対応がない場合、黒色の画素だけは正常に見えますが、色付き文字は
余分なバイトによって画素境界がずれ、ノイズ状になります。

同じ問題は表示領域の座標にも影響します。たとえば座標239は
`0xef`の1バイトとして送る必要があります。UTF-8に展開されると
コマンド長が変わるため、画面の一部だけが黒くクリアされ、残りに
古いGRAMのノイズが表示されることがあります。

## トラブルシューティング

Waveshareモジュールでは、まず
`examples/st7789_debug_console_verify.rb`の設定値を使います。

- 画面の一部だけが黒く、残りがノイズの場合は、`CASET`または
  `RASET`の座標バイト破損が疑われます。現在の`setbyte`ベースの
  ドライバを使用してください。
- 色付き画素や文字が崩れる場合は、RGB565バイト破損が疑われます。
  バイナリ生成処理を`String#<< integer`へ戻さないでください。
- 正しい画像に点状ノイズだけが混ざる場合は、配線またはSPI信号品質を
  確認します。GNDとジャンパ線の長さを確認してから、標準の24 MHzを
  下げてください。
- 回転だけが違う場合は`:madctl`を変更します。通信確認中はWaveshare
  標準の`0x70`を維持してください。

## API

よく使うメソッド:

- `write_line(text)`: 選択したスクロールモードでデバッグ行を1行追加する。
- `puts(text)`: `write_line` 用の簡易メソッド。
- `clear`: LCDをクリアし、行リングバッファもリセットする。
- `backlight(on)`: backlight pin がある場合にON/OFFする。
- `color(fg, bg = nil)`: 以後の文字色を変更する。
- `fill_rect(x, y, w, h, color)`: 矩形を塗る。
- `draw_char(x, y, ch, fg, bg)`: 8x8 のASCII文字セルを描く。
- `draw_text_line(row, text)`: 指定行にテキストを描く。

低レベルST7789ヘルパ:

- `command(byte)`
- `data(byte_or_string)`
- `set_window(x0, y0, x1, y1)`
- `write_pixels(rgb565_data)`

## 検証サンプル

次のサンプルを使います。

```ruby
examples/st7789_debug_console_verify.rb
```

ファイル冒頭のピン定数を実際の配線に合わせて変更し、`lib/st7789_debug_console.rb` と一緒に R2P2 へ配置して実行します。画面をクリアし、基本情報を表示したあと、1秒ごとにカウンタを追記します。

## MPU-6050 デバッグとの統合

センサのデバッグでは、詳細ログはUSB serialへ出し、LCDには短い状態行だけを出すのが扱いやすいです。

表示候補:

- `EVENT count`
- 選択軸
- `gyro_dps`
- `angle`
- `dt_skipped`

高レートの全サンプルをLCDへ出すのは避けてください。このコンソールはSPIへ直接テキストセルを描くため、ステータス表示には十分ですが、高頻度テレメトリ表示には向きません。

## 制限

- ASCII固定幅フォントのみ。
- 日本語フォントなし。
- 画像描画なし。
- 全画面framebufferなし。
- `:page`は物理行0へ戻る前に前ページを消去する。
- `:wrap`は物理行を循環上書きし、他の古い行を表示に残す。
- `:redraw`は通常のスクロール表示になるが、全画面を転送する。
- host test では実LCDの表示確認は行わない。

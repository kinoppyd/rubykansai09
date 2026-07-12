# picoruby-ble-passive-scan.patch

対象パッチ: [`patches/picoruby-ble-passive-scan.patch`](../../patches/picoruby-ble-passive-scan.patch)

## パッチの概要

PicoRubyのmruby向けBLE central bindingで、`set_scan_params(:passive, ...)`を
BTstackへ渡す際のscan typeを`1`から`0`へ修正するパッチである。

変更対象は次の1ファイル、1行だけである。

```text
mrbgems/picoruby-ble/src/mruby/ble_central.c
```

BTstackのscan typeは次の値を使う。

| 値 | 動作 |
| ---: | --- |
| `0` | Passive scan |
| `1` | Active scan |

パッチ適用前は`:passive`と`:active`の両方が`1`へ変換されていた。適用後は
`:passive`だけが正しく`0`になる。

## 必要な理由

本プロジェクトのhostはセンサのadvertising packetを受信できればよく、scan requestを
送ってscan responseを取得する必要がない。ところが元のmruby bindingでは
`:passive`指定でもactive scanが開始される。

この誤りには次の影響がある。

- APIで指定した動作と実際のradio動作が一致しない。
- 不要なscan requestとscan responseが発生する。
- BLE event queueへ入るadvertising関連eventが増える。
- 周囲にBLE機器が多い環境で、重要なconnection/GATT eventが処理されるまでの遅延が
  増える。
- Scan responseを通常のconnectable advertisingと誤認しやすくなり、接続判定の診断を
  難しくする。

2センサhostでは接続済みの1台を維持しながら未接続sensorをscanするため、不要なradio
trafficを避ける意味でもpassive scanを正しく指定する必要がある。

## 詳細な技術的解説

### Ruby APIからBTstackまでの変換

Ruby側は次のようにscan条件を指定する。

```ruby
ble.set_scan_params(:passive, 0x30, 0x30)
```

`scan_interval`と`scan_window`の単位は0.625 msであるため、`0x30`は30 msに
相当する。この例ではwindowとintervalが同じなのでscan dutyは100%になる。

mruby bindingの`mrb_set_scan_params`はsymbolを数値へ変換し、最終的に
`BLE_central_set_scan_params`からBTstackの`gap_set_scan_params`へ渡す。元コードでは
`:passive`分岐でも`scan_type_num = 1`だったため、Ruby APIの指定がC層で失われていた。

### mruby/c側との違い

このパッチはmruby向けファイルだけを変更する。mruby/c向けの
`src/mrubyc/ble_central.c`は、すでに次の対応になっているためである。

```text
passive -> 0
active  -> 1
```

R2P2 PicoRuby/Pico 2 W hostはmruby側bindingを使うため、この差分が必要になる。

### Active scanの扱い

このパッチはactive scanを新規実装するものではない。mruby側の`:active`分岐には
引き続き`mrb_notimplement`があり、mruby/c側もactive scanを未実装として例外にする。
修正範囲はpassive指定の数値変換だけである。

## 他に必要な説明事項

### 適用順と依存関係

BLE host用patch chainの最初に適用する。このパッチ自体は他のpatchへ依存しない。

```text
1. picoruby-ble-passive-scan.patch
2. picoruby-ble-central-notification-listener.patch
3. picoruby-ble-all-notifications.patch
4. picoruby-ble-central-gap-meta.patch
5. picoruby-ble-preserve-state-event.patch
6. picoruby-ble-two-connections.patch
```

### 適用対象

Host firmwareだけに必要である。BLE peripheralとしてadvertiseするspeed/cadence sensor
firmwareには不要である。

### 検証方法

1. `git apply --check`で対象PicoRuby treeへ適用可能か確認する。
2. Hostを起動し、`multi_central_up`と`scan_started`を確認する。
3. `scan_reports`が増え、対象sensorのconnectable advertisingから接続へ進むことを確認する。
4. Scan responseだけを接続対象にしていないことを確認する。

このリポジトリではPicoRuby
`b0c1c4828b82b267dab9cabf4a372c46c2a1075e`で連続patch適用とUF2 buildを確認した。
別revisionでは対象行がupstreamで修正済みかを先に確認し、修正済みならこのpatchを
重ねて適用しない。

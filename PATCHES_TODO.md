# PicoRuby Patch再編TODO

最終更新: 2026-07-13 JST

## 目的

`patches`配下の7 patchを、機能境界、適用対象、依存関係、検証可能性の観点から再編する。
単にfile数を減らすのではなく、次を満たすpatch setを作る。

- Patch名と変更内容が一致する。
- 1 patchだけ適用した中間状態でも、可能な限り意味のある状態になる。
- Host、sensor、displayあり/なしのbuild差を明確にする。
- CleanなPicoRuby treeへ決められた順序で再現可能に適用できる。
- mruby/mruby-c、BTstack、R2P2 CMakeの境界を混同しない。
- 将来PicoRubyへ同等修正が入った場合、不要になったpatchを判定できる。

この文書は再編計画と実施記録を兼ねる。Software側の再編と検証は完了しており、
「実機検証」に残る項目は新しい5 patch構成でbuildしたUF2による再確認待ちである。

## 調査基準

### 対象version

現在のpatch chainで実機・build確認済みの基準は次のとおり。

| Component | Revision |
| --- | --- |
| PicoRuby | `b0c1c4828b82b267dab9cabf4a372c46c2a1075e` |
| Pico SDK | `a1438dff1d38bd9c65dbd693f0e5db4b9ae91779` |
| Pico SDK version | 2.2.0 |
| Host | Raspberry Pi Pico 2 W / PicoRuby mruby VM |
| Sensor | Raspberry Pi Pico 2 W / BLE peripheral 1 connection |

別revisionへ適用するときは、patchを機械的に移植する前にupstream側へ同等修正が入って
いないか確認する。

### 評価軸

各patchを次の基準で評価した。

1. 同じ不具合または同じruntime capabilityを構成する変更か。
2. Patch単独で利用するbuild variantがあるか。
3. 適用有無をhost/sensor/display buildごとに切り替える必要があるか。
4. 同じsource hunkへ連続適用することによる偶発的な順序依存があるか。
5. Upstreamへ個別提案できる独立した修正か。
6. 現在のRuby codeまたはlegacy検証経路から実際に参照されているか。
7. Static RAM、Ruby heap、event lossへ与える影響を独立して測定できるか。

## 現行patchの判定

| 現行patch | 判定 | 移行先または扱い |
| --- | --- | --- |
| `picoruby-ble-passive-scan.patch` | 維持 | 同名で独立維持 |
| `picoruby-ble-central-notification-listener.patch` | 統合 | `picoruby-ble-notification-listeners.patch` |
| `picoruby-ble-all-notifications.patch` | 統合 | `picoruby-ble-notification-listeners.patch` |
| `picoruby-ble-central-gap-meta.patch` | 統合 | `picoruby-ble-central-event-delivery.patch` |
| `picoruby-ble-preserve-state-event.patch` | 統合・修正 | `picoruby-ble-central-event-delivery.patch` |
| `picoruby-ble-two-connections.patch` | 維持 | Host専用の独立patchとして維持 |
| `picoruby-gc9a01-speedometer.patch` | 維持 | Display build専用の独立patchとして維持 |

推奨patch数は7本から5本になる。

```text
picoruby-ble-passive-scan.patch
picoruby-ble-notification-listeners.patch
picoruby-ble-central-event-delivery.patch
picoruby-ble-two-connections.patch
picoruby-gc9a01-speedometer.patch       # display buildだけ
```

## 統合するpatch

### 1. Notification listener 2本

統合対象:

```text
picoruby-ble-central-notification-listener.patch
picoruby-ble-all-notifications.patch
```

新しい名前:

```text
picoruby-ble-notification-listeners.patch
```

#### 統合理由

両patchは同じBTstack API、同じC header、同じRP2040 port、同じmruby/mruby-c binding、同じ
RBSを拡張する。後者は前者が追加した変数とmethodを前提にしたincremental diffであり、
単独では適用できない。

機能的にも次の2種類のlistenerを提供する1 capabilityとして扱う方が自然である。

- 特定connection + 特定value handle用listener。
- 全connection + 全characteristic用wildcard listener。

現在のsingle sensor検証経路は前者、`MultiUARTCentral`は後者を使う。どちらもまだ必要で
あり、API自体は削除しない。

> 後続cleanup（2026-07-17）でsingle sensor runtime経路は削除した。Firmwareのspecific
> listener bindingは汎用API互換として残すが、現行appはwildcard listenerだけを使う。

#### 統合時に維持するAPI

```ruby
listen_for_characteristic_value_updates(connection_handle, value_handle)
listen_for_all_characteristic_value_updates
stop_listening_for_all_characteristic_value_updates
```

#### 統合時の注意

- Specific listenerとwildcard listenerを同時登録すると同じnotificationが重複配送される
  可能性がある。Runtimeではどちらか一方だけを選ぶ。
- Static listener構造体はBTstack登録中に有効である必要があるため、stack変数へ変更しない。
- CCCD writeはlistener登録とは別であり、connectionごとに維持する。
- Wildcard listenerのregistered flagとHCI power cycleのlifecycleを揃える。
- mrubyとmruby-cのbinding、RBSを1 patch内で同時に更新する。

### 2. Central event転送とmruby event queue

統合対象:

```text
picoruby-ble-central-gap-meta.patch
picoruby-ble-preserve-state-event.patch
```

新しい名前:

```text
picoruby-ble-central-event-delivery.patch
```

#### 統合理由

前者はBTstack callbackからRubyへ渡すeventを選び、後者は選ばれたeventをRuby loopが読む
まで保持する。どちらか一方だけでは、central state machineへeventを安定配送できない。

- 転送対象を増やしてsingle-packet bufferのままにすると上書きが増える。
- Queueだけ追加しても`HCI_EVENT_META_GAP`やdisconnectを転送しなければ接続状態を更新できない。

「Native callbackからRuby central state machineまでのevent delivery」を1つの意味論的単位と
し、無効な中間構成を作らないようにする。

#### 統合patchに含める内容

- `BTSTACK_EVENT_STATE`の転送とHCI working状態の追跡。
- Working後のcommand status/complete転送。
- `HCI_EVENT_DISCONNECTION_COMPLETE`の転送。
- `HCI_EVENT_LE_META`と`HCI_EVENT_META_GAP`の転送。
- Advertising/GATT/notification eventの既存転送。
- mruby向け容量8 event queue。
- Queue満杯時のevent優先度制御。
- mruby-c側single-packet実装の明示的な維持。

#### Queue policyで修正すべき点

現行queueは全`HCI_EVENT_COMMAND_STATUS`をdiscardableにする。一方、Ruby centralは
LE Create Connection (`0x200d`) のcommand statusが失敗した場合にpending slotをresetする。
Queue満杯時にこのeventを捨てると、connection failureで`connecting`のまま停止する可能性が
ある。

統合時に少なくとも次をcritical commandとして保護する。

```text
HCI_EVENT_COMMAND_STATUS + opcode HCI_LE_CREATE_CONNECTION (0x200d)
```

`HCI_EVENT_COMMAND_COMPLETE`はopcodeごとに必要性を確認し、scan enable (`0x200c`)など診断・
回復に使うeventだけを保護する。全command eventを無条件にcriticalへするとHCI初期化noiseで
queueを圧迫するため採用しない。

#### 統合時に追加検討する診断

Memory増加を抑えるため初期実装では必須にしないが、次の固定幅counterを追加できるか確認する。

- Event type別drop count。
- Queue最大depth。
- Scan report drop count。
- Critical eventを押し出した回数。

Ruby Hashやevent payloadの保存は行わず、C側の固定整数だけを候補にする。

## 独立維持するpatch

### picoruby-ble-passive-scan.patch

mruby bindingの`:passive`をBTstack値`0`へ直す1行のupstream bug fixである。Notification、
queue、connection数とは独立しており、単一接続hostでも必要になる。

PicoRuby `b0c1c482`では未修正のため現在は必要である。将来revisionで`:passive -> 0`に
修正済みなら、このpatchは削除する。

### picoruby-ble-two-connections.patch

BTstackのHCI/GATT static pool数を変えるbuild capacity patchであり、runtime API patchとは
分離する。

- 2sensor host: 必要。
- 単一sensor host: 不要。
- Speed/cadence peripheral firmware: 不要。

#### 将来の改善候補

現在はmacroを`1`から`2`へ直接変更するため、host/sensorで別build treeまたはpatch適用状態を
分ける必要がある。次の形へ変更できるか別checkpointで評価する。

1. `btstack_config.h`の値を`#ifndef`でoverride可能にする。
2. R2P2 CMake cache optionからHCI/GATT slot数を渡す。
3. Defaultは`1`を維持し、2sensor host buildだけ`2`を指定する。

この改善には`tasks/picoruby/r2p2.rake`からCMake optionを渡す経路も必要になる。Patch再編の
必須範囲には含めず、5本化が安定した後に実施可否を判断する。

### picoruby-gc9a01-speedometer.patch

Native mrbgem選択、C++ source収集、LovyanGFX追加、compile definition、linkは、GC9A01を
含むUF2を成立させる1つのatomic build featureである。途中で分割すると、gemは選択されたが
C++/LovyanGFXがlinkされない中間状態を作るため、このリポジトリでは1本のまま維持する。

- BLEだけのhost: 不要。
- Speed/cadence sensor: 不要。
- Dual GC9A01 host: 必要。

Upstreamへ提案する場合に限り、汎用的なR2P2 C++ source対応とGC9A01固有integrationを別commitに
分ける余地がある。ローカルbuild artifactとしてのpatch分割は行わない。

## 不要patch・不要機能の判定

### 完全に削除できるpatch

PicoRuby `b0c1c482`を対象とする限り、機能ごと完全に不要なpatchはない。

ただし統合完了後、次の4 fileは新patchへ置き換わるため削除する。

```text
picoruby-ble-central-notification-listener.patch
picoruby-ble-all-notifications.patch
picoruby-ble-central-gap-meta.patch
picoruby-ble-preserve-state-event.patch
```

### Specific notification listener API

現在の2sensor host appはwildcard listenerだけを使うため、specific listenerはmain hot pathには
不要である。ただし`BLECycleHost::UARTCentral`と`custom_cycle_uart_demo`の単一接続回帰経路が
利用する。Legacy単一接続経路を正式に廃止するまでは残す。

> このlegacy経路は2026-07-17のcleanupで廃止した。

### HCI_EVENT_COMMAND_COMPLETE転送

`MultiUARTCentral`は主にcommand statusを使うが、単一接続runtime patchはcommand completeを
診断に使う。Specific listenerと同様、legacy経路を維持する間は削除しない。

### GC9A01 patch

No-display hostでは不要だが、optional build patchであってrepositoryから不要という意味では
ない。BLE問題の切り分け用に適用しないvariantを維持する。

## 分割の判定

現時点で必ず分割すべきpatchはない。

| Patch | 分割しない理由 |
| --- | --- |
| Passive scan | すでに1行の独立bug fix |
| Notification統合patch | C API、binding、RBSをatomicに揃える必要がある |
| Event delivery統合patch | Event選別と保持を片方だけ適用すると不完全 |
| Two connections | 2定数だけの独立capacity変更 |
| GC9A01 | Gem選択からC++ linkまで揃わないとbuild不能 |

GC9A01の汎用C++対応をupstream commitとして分ける案と、2接続数をCMake option化する案は、
patch chain再編後の別作業とする。

## 推奨する新patch適用順

### Sensor firmware

Host用patchは適用しない。BTstack connection poolは既定値`1`を維持する。

### Host、GC9A01なし

```text
1. picoruby-ble-passive-scan.patch
2. picoruby-ble-notification-listeners.patch
3. picoruby-ble-central-event-delivery.patch
4. picoruby-ble-two-connections.patch
```

### Host、dual GC9A01

```text
1. picoruby-ble-passive-scan.patch
2. picoruby-ble-notification-listeners.patch
3. picoruby-ble-central-event-delivery.patch
4. picoruby-ble-two-connections.patch
5. picoruby-gc9a01-speedometer.patch
```

## 実装ステップ

### 0. Baseline保護

- [x] 現在の7 patchと`docs/patches`を、再編前baselineとしてcommitする。
- [x] PicoRuby `b0c1c482`のclean checkoutを変更せず保持する。
- [x] Patch検証用の一時treeをclean checkoutと分離する。
- [x] 現行順で7 patchを連続適用できることを再確認する。
- [x] 現行patch適用後のcombined diffを保存し、新patchとの比較基準にする。
  - Host: `b83399783f2f4e4d1ceb5959e7ebb3a18cb0a44805029edd13ecb3af9749bad4`
  - Host + display: `1b5586e2a4e575c921837175e5bc25baf67572211953b4f501fdcff8b30a326c`
- [x] 現行host ELFのtext/BSS/heap余裕とnative symbolを記録する。
  - `docs/ble/multi_sensor_ble_uart_feasibility.ja.md`の最終host UF2 buildに記録済み。
- [x] CRuby test suiteのrun/assertion数を記録する。
  - Baseline: `85 runs, 328 assertions, 0 failures, 0 errors`。

Commit checkpoint:

```text
Document current PicoRuby patches
```

### 1. Patch chain検証script

- [x] Pinned PicoRuby revisionを検査するscriptを追加する。
- [x] Temporary treeへpatchを順番に適用し、失敗したpatch名を表示する。
- [x] 検証終了後にtemporary treeを削除し、clean source treeを汚さない。
- [x] Host no-displayとdual-displayのpatch listを引数または固定profileで選択できるようにする。
- [x] `git diff --check`と未適用/重複適用を検出する。
- [x] Script自体がnetwork accessを要求しないようにする。

Commit checkpoint:

```text
Add PicoRuby patch chain verification
```

### 2. Notification patch統合

- [x] Clean baselineへ既存notification 2 patchだけを順番に適用する。
- [x] そのcombined diffから`picoruby-ble-notification-listeners.patch`を生成する。
- [x] Specific listener API 1組とwildcard listener API 1組を維持する。
- [x] mruby/mruby-cの引数検証とmethod登録を確認する。
- [x] RBSに3 methodが揃うことを確認する。
- [x] Static listenerの二重登録、停止、再登録を確認する。
- [x] Specificとwildcardを同時使用しないruntime契約をdocument化する。
  - 本文の「統合時の注意」へ記載し、最終patch documentにも反映する。
- [x] 新patch単体をclean baselineへ適用できることを確認する。
- [x] Legacy単一接続hostと2sensor multi-centralの両方をtestする。
  - 旧2 patchとのcombined diff SHA-256は同じ
    `4f8ee1894ee60fefdd1a54ad957ab992a96eeca9580531e4124f28507ddb26a6`。
  - Ruby regression: `85 runs, 328 assertions, 0 failures, 0 errors`。

Commit checkpoint:

```text
Consolidate BLE notification listener patches
```

### 3. Central event delivery patch統合

- [x] Clean baselineへ既存central GAP/event queue 2 patchを適用したcombined diffを作る。
- [x] `picoruby-ble-central-event-delivery.patch`として再生成する。
- [x] Central event whitelistとmruby queueを同じpatchへ含める。
- [x] `central_hci_working`をnotification static変数へ依存しない位置/contextへ置く。
- [x] Connection complete全形式とdisconnectを非破棄eventとして確認する。
- [x] LE Create Connection command status `0x200d`をcritical eventとして保護する。
- [x] その他command eventのdiscard policyをopcode単位で決める。
  - `0x200d`以外のcommand statusと全command completeは引き続きdiscardableとする。
- [x] GATT result/query complete/notificationのFIFO順を維持する。
- [x] Queue途中削除時のpointer、size、tail、count更新を再確認する。
- [x] mruby-cが意図せずqueue版へ変わっていないことを確認する。
- [x] `MultiUARTTransport`の最大8 event/tickとqueue capacity 8の関係をtestする。
- [x] Scan report flood中もuser callbackが20 ms単位で戻ることをtestする。
  - Multi-central: `10 runs, 46 assertions`。
  - Bounded transport: `1 run, 5 assertions`。

Commit checkpoint:

```text
Consolidate BLE central event delivery patches
```

### 4. 独立patchのrefresh

- [x] Passive scan patchをclean baselineから再生成し、不要なindex/context churnを除く。
  - 現行差分が1行だけで追加churnがないため、そのまま維持した。
- [x] mruby-c側がすでに`:passive -> 0`であることをdocumentに維持する。
- [x] Two-connections patchを2 macroだけの差分として維持する。
- [x] GC9A01 patchがnotification/event patchへ依存していないことを確認する。
- [x] LovyanGFX path、C++ glob、primary/secondary pin definitionを再確認する。
- [x] 各独立patchの`git apply --check`を実行する。

Commit checkpoint:

```text
Refresh independent PicoRuby patches
```

### 5. 旧patchの削除とdocument移行

- [x] 新patch chainが通るまで旧4 patchを残す。
- [x] 同等性確認後に旧notification 2 patchを削除する。
- [x] 同等性確認後に旧event delivery 2 patchを削除する。
- [x] `docs/patches`へ新patch 2本の日本語解説を追加する。
- [x] 旧patch documentは削除するか`docs/patches/archive`へ移すかを決める。
  - 統合後の運用時に誤って旧patchを参照しないよう、旧4文書は削除した。統合経緯は新文書と
    本TODOに残す。
- [x] `cadence_sensor_demo.ja.md`のpatch順を5本構成へ更新する。
- [x] `dual_gc9a01_cycle_host.ja.md`のpatch順を更新する。
- [x] `custom_cycle_uart_demo.ja.md`の旧patch名参照を更新する。
- [x] `multi_sensor_ble_uart_feasibility.ja.md`のpatch linkを更新する。
- [x] `CADENCE_TODO.md`と`BLE_TODO.md`の履歴記述を壊さず、現行patch名だけ更新する。
  - `CADENCE_TODO.md`の現行patch名を更新した。`BLE_TODO.md`には旧4 patch名の参照がなく、
    変更不要だった。
- [x] `patches/*.patch`と`docs/patches/*.ja.md`が1対1であることを検査する。

Commit checkpoint:

```text
Replace legacy PicoRuby patch chain
```

### 6. Clean applyとnative build検証

- [x] PicoRuby `b0c1c482`のtemporary clean treeへ新4 BLE patchを順番に適用する。
- [x] 同じtreeへGC9A01 patchを追加適用する。
- [x] Host no-display UF2をclean buildする。
- [x] Host dual-GC9A01 UF2を別build treeでclean buildする。
- [x] Sensor UF2はhost patchなしのclean treeからbuildする。
- [x] Host ELFにwildcard listener API symbolがあることを確認する。
- [x] Sensor ELFにhost専用wildcard listener APIを含めていないことを確認する。
- [x] Host mapでHCI/GATT poolが2slotあることを確認する。
- [x] Sensor mapでpoolが1slotのままであることを確認する。
- [x] 旧buildと新buildのtext/BSS/heap差を比較する。
- [x] 意図したqueue policy変更以外にnative diffがないことを確認する。

検証結果:

| Profile | text | BSS | Heap余裕 | HCI storage | GATT storage | UF2 SHA-256 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Sensor | 2,259,168 | 442,124 | 49,268 | 760 bytes / 1 slot | 144 bytes / 1 slot | `78621b4c7d2baaaa781340f98fd011c654e3d3ce8368abcf60b5a165a679a8ea` |
| Host no-display | 2,260,288 | 443,128 | 48,264 | 1,520 bytes / 2 slots | 288 bytes / 2 slots | `20c6e75fa6f657f29e647a92f373f71c11556ad000dd89c27777ed5a0212af4c` |
| Host dual-display | 2,354,052 | 444,748 | 46,180 | 1,520 bytes / 2 slots | 288 bytes / 2 slots | `6d149d7653d60331cb44329e96c65e4d97d870007e6d89070f6b78a65cbb43ac` |

- Pinned clean treeへのcombined diff SHA-256はhostが
  `cf3e62f6e6a7657a0fc4c101ab20a5583b270f9e18865d93baa6fef34b70c657`、
  host-displayが`73a6a7b544b06a3e6ba0d10a1b8c55c988147d66beeb4ce8b82083503b0399a5`。
- 旧buildとのtext/BSS/heap差は0 bytes。再編によるbinary size増加はない。
- Notification統合patchは旧2本のcombined diffと完全一致する。Event delivery統合patchの
  意味上の差分はLE Create Connection command status (`0x200d`) の保護だけである。
- Host ELFには`BLE_listen_for_all_characteristic_value_updates`と停止APIがあり、sensor ELFには
  どちらもない。

Commit checkpoint:

```text
Verify consolidated PicoRuby patch builds
```

### 7. Ruby回帰検証

- [x] 全CRuby testを実行する。
- [x] `mrbc -c`でspeed sensor appを確認する。
- [x] `mrbc -c`でcadence sensor appを確認する。
- [x] `mrbc -c`でhost appと新BLE libraryを確認する。
- [x] Specific listenerを使うlegacy `UARTCentral`経路を確認する。
- [x] Wildcard listenerで同じvalue handleをconnection handle別に配送するtestを確認する。
- [x] Connection failure command statusを失わずscanへ戻るtestを追加する。
- [x] Queue満杯時にscan reportよりcritical eventを優先するtest方法を決める。

CRuby回帰結果は`85 runs, 328 assertions, 0 failures, 0 errors`。`mrbc -c`はsensor 2 app、
host app、multi/single centralとnotification処理libraryのすべてで`Syntax OK`となった。
Native優先度はhost-native test buildでadvertising report 8件を注入後、`0x200d` command statusを
投入してscan reportが押し出されることを直接検査する。Production firmwareへevent注入APIは
追加しない。詳細は`docs/patches/picoruby-ble-central-event-delivery.ja.md`に記録した。

### 8. 実機検証

以下は再編前の等価な7 patch構成では確認済みの経路を含むが、完了判定は新しい5 patch構成の
UF2へ入れ替えた後に行う。特に時間指定のある試験はsoftware検証で代替しない。

- [ ] Speed sensor 1台だけで接続、通知、表示を確認する。
- [ ] Cadence sensor 1台だけで接続、通知、表示を確認する。
- [ ] 2sensorが異なるconnection handleで同時readyになることを確認する。
- [ ] 両sensorの250 ms notificationを最低10分確認する。
- [ ] `reader_gap_count`が継続的に増えないことを確認する。
- [ ] Speedだけを再起動し、cadence接続と表示が継続することを確認する。
- [ ] Cadenceだけを再起動し、speed接続と表示が継続することを確認する。
- [ ] 接続失敗または圏外sensorがあってもhost callbackが停止しないことを確認する。
- [ ] Dual GC9A01描画中にBLE sequence gapが増えないことを確認する。
- [ ] 最低30分の2sensor + dual-display試験を実施する。

## Build/test matrix

| Profile | BLE patch | 2conn | GC9A01 | 必須確認 |
| --- | --- | --- | --- | --- |
| Sensor | なし | なし | なし | Peripheral advertise/notify、pool 1 |
| Legacy single host | Passive + listeners + event delivery | なし | 任意 | Specific listener回帰 |
| Multi host no display | Passive + listeners + event delivery | あり | なし | 2handle、wildcard routing |
| Multi host dual display | Passive + listeners + event delivery | あり | あり | 2handle、2画面、heap余裕 |

## 完了条件

- [x] 現行7 patchが推奨5 patchへ置き換わっている。
- [x] Patch名と変更内容が一致している。
- [x] 旧patch 4本へのactiveなdocument linkが残っていない。
- [x] 新patch chainがpinned clean PicoRuby treeへ連続適用できる。
- [x] Sensor、host no-display、host dual-displayの3 UF2がclean buildできる。
- [x] Legacy specific listenerとmulti wildcard listenerの両経路が動作する。
- [ ] 2sensorを250 ms周期で同時受信できる。
- [ ] Connection failure、disconnect、再接続でstate machineが停止しない。
- [ ] 30分試験でNoMemoryErrorと継続的sequence gapがない。
- [x] 各patchに対応する日本語documentが`docs/patches`にある。

## Rollback方針

旧patchとその文書は現行treeから削除したが、再編前baseline commit `b010a1f`に保存されている。
新しいUF2の実機検証で問題が出た場合は、working treeへ旧patchを常設し直さず、baseline commit
から一時build treeへ旧7本を取り出して比較する。次のどの境界で差が出たかを切り分ける。

1. Notification registration。
2. Native event forwarding。
3. mruby event queue。
4. BTstack 2connection pool。
5. GC9A01 C++/LovyanGFX link。

Notification統合は旧combined diffと完全一致する。Event deliveryで挙動が変わり得る箇所は
`0x200d` command statusの保護だけなので、問題時はまずこのqueue policyを比較する。統合commit、
旧patch削除commit、build検証commitを分けた履歴から原因範囲を追跡する。

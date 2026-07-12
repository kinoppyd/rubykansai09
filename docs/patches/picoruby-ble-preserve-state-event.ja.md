# picoruby-ble-preserve-state-event.patch

対象パッチ: [`patches/picoruby-ble-preserve-state-event.patch`](../../patches/picoruby-ble-preserve-state-event.patch)

## パッチの概要

PicoRuby mruby版BLE event受け渡しをsingle-packet bufferから容量8のevent queueへ変更し、
HCI state、connection complete、GATT result、notificationなどがRuby loopで読む前に
上書きされる問題を軽減するパッチである。

変更対象は次の2ファイルである。

| ファイル | 変更内容 |
| --- | --- |
| `mrbgems/picoruby-ble/src/ble.c` | 旧single-packet変数をmruby/c専用に限定 |
| `mrbgems/picoruby-ble/src/mruby/ble.c` | mruby用queue、満杯時の選別、dequeueを実装 |

Queue capacityはcompile-time固定の`8`である。

## 必要な理由

元実装の`BLE_push_event`は、未処理eventを1個だけ保持する。新しいeventが到着すると
以前のbufferをfreeして新eventへ置き換えるため、Rubyの`pop_packet`より速くeventが
連続すると中間eventが失われる。

BLE central起動と接続ではeventがburstしやすい。

- HCI初期化commandの完了
- `BTSTACK_EVENT_STATE`
- Advertising report
- LE Create Connection command status
- Connection complete
- 複数のGATT service/characteristic query result
- GATT query complete
- Notification

実機ではevent lossにより次の症状が発生した。

- `UART Central up`が出ず、HCI stateが`off`のままになる。
- `gap_connect 0`の後、connection completeを失って接続待ちから進まない。
- 接続後にcustom service resultを失い、`service_not_found`になる。
- CCCD設定後もnotification eventを継続処理できない。

これらを防ぐため、最低限のFIFO queueと重要度に応じた満杯時処理を追加する。

## 詳細な技術的解説

### Queue構造

mruby向け実装は次の固定長管理領域を持つ。

```c
#define BLE_EVENT_QUEUE_CAPACITY 8
static uint8_t *packet_queue[BLE_EVENT_QUEUE_CAPACITY];
static uint16_t packet_queue_size[BLE_EVENT_QUEUE_CAPACITY];
static uint8_t packet_queue_head;
static uint8_t packet_queue_count;
```

各event payloadは`mrb_malloc`で実サイズ分を確保し、pointerとsizeを固定配列へ保存する。
`mrb_pop_packet`はhead eventからRuby Stringを生成し、元bufferをfreeしてheadを進める。

固定なのはevent件数であり、payload buffer自体は動的確保される。したがって最大heap消費は
8件分の実event sizeとallocator overheadで決まる。

### 満杯時の優先度

Queueが満杯の場合、eventを次のように分類する。

明示的に保護するevent:

- `BTSTACK_EVENT_STATE`
- LE Connection Complete
- Enhanced LE Connection Complete v1/v2
- GAP LE Connection Complete

破棄可能とするevent:

- GAP/raw HCI advertising report
- `HCI_EVENT_COMMAND_COMPLETE`
- `HCI_EVENT_COMMAND_STATUS`
- Size 0のevent

上記以外のGATT result、query complete、notificationなどは非破棄eventとして扱う。

満杯時のpolicyは次のとおり。

1. 新event自体が破棄可能なら、新eventをqueueへ入れずに捨てる。
2. 新eventが非破棄なら、queue内で最初の破棄可能eventを削除して空きを作る。
3. Queue内に破棄可能eventがなければ、最古eventを削除して新eventを入れる。

このため重要eventを絶対に失わない保証ではない。8件すべてが非破棄eventのburstなら最古の
eventを失う。ただしscan reportでqueueが埋まった場合にconnection/GATT eventを優先できる。

### Queue途中要素の削除

破棄対象がhead以外の場合、ring上の後続pointer/sizeを1要素ずつ前へ詰める。Capacityが8と
小さいため、最大7要素のshiftで済む。削除したpayloadは必ず`mrb_free`し、tail slotを
`NULL`と0へ戻す。

### Mutexと残るloss条件

`packet_mutex`がtrueの間に`BLE_push_event`が呼ばれた場合は、そのeventを即時破棄する。
このパッチはlock-free queueやinterrupt-safe critical sectionを導入するものではない。
Queue化は連続eventの上書きを減らすが、すべての競合を排除しない。

### mruby/cを変更しない理由

共通`src/ble.c`の旧`packet`と`packet_size`を
`PICORB_VM_MRUBYC`の条件内へ移し、mruby/cでは従来のsingle-packet実装を維持する。
新queueは`src/mruby/ble.c`だけに実装される。

このプロジェクトのPico 2 W hostはPicoRuby/mrubyを使うため対象になるが、FemtoRuby/
mruby-c firmwareへ同じ保証は提供しない。

## 他に必要な説明事項

### Ruby loop側のstarvation対策

Queueを`while pop_packet`で空になるまで処理すると、advertisingが高頻度で到着する環境では
queueが空にならず、アプリの周期callbackへ戻れないことがある。本プロジェクトの
`BLECycleHost::MultiUARTTransport`は1 tickあたり最大8 eventを処理し、20 msごとに
user callbackへ戻す。

Queue patchとbounded drainは別の問題を解決するため、両方が必要である。

### Counterがないこと

現在のpatchはdrop count、最大queue depth、event type別drop数を公開しない。Sequence gapが
増える場合は、まずRuby側の`FrameReader#gap_count`で観測する。原因分析が必要になった場合は
native counter追加を検討し、根拠なくcapacityを増やさない。

### 適用順

`picoruby-ble-central-gap-meta.patch`の後、`picoruby-ble-two-connections.patch`の前に適用する。
Central gap patchが転送するeventを、このqueueで保持する構成である。

### メモリ上の注意

Queue管理配列はstaticだがpayloadはmruby heapから確保する。受信量が多い場合は短命なStringと
buffer allocationが増える。Hostのheap余裕、NoMemoryError、sequence gapを長時間試験で
確認する必要がある。

### 検証方法

- HCI起動時に`multi_central_up`が安定して出る。
- Advertisingが多い環境でも5秒ごとのstatus callbackが継続する。
- Connection complete後にservice/characteristic discoveryが最後まで進む。
- 2台から250 ms周期で受信し、`reader_gap_count`が増え続けない。
- 30分以上の試験でNoMemoryErrorが発生しない。

PicoRuby `b0c1c4828b82b267dab9cabf4a372c46c2a1075e`でbuildと実機接続を確認した。

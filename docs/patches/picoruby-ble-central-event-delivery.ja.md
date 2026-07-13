# picoruby-ble-central-event-delivery.patch

対象パッチ: [`patches/picoruby-ble-central-event-delivery.patch`](../../patches/picoruby-ble-central-event-delivery.patch)

## パッチの概要

PicoRuby BLE centralのnative callbackからRuby state machineまで、接続管理に必要なeventを
選択して容量8のFIFO queueで配送するパッチである。

主な変更は次のとおり。

- HCI working状態、command result、disconnect、LE/GAP connection eventをRubyへ転送する。
- mruby版のsingle-packet bufferを容量8のevent queueへ置き換える。
- Queue満杯時はscan reportなどを先に破棄し、状態遷移に必要なeventを優先する。
- LE Create Connection command status (`0x200d`) をcritical eventとして保護する。
- mruby/c版は従来のsingle-packet実装を維持する。

旧`picoruby-ble-central-gap-meta.patch`と`picoruby-ble-preserve-state-event.patch`を統合し、
転送対象だけ増えて保持機構が不足する中間構成をなくした。旧2本からの意味上の変更は、
`0x200d`のcommand statusをqueue満杯時にも保護する点だけである。

## 必要な理由

Pico 2 Wの実機ではconnection completeが標準`HCI_EVENT_LE_META`だけでなく、BTstack固有の
`HCI_EVENT_META_GAP`として届く場合がある。元のPicoRuby portは後者とdisconnect、接続command
statusをRubyへ渡さないため、controller側では接続済みでもRuby側が`connecting`のまま停止した。

さらに元のmruby event受け渡しは未処理packetを1個しか保持しない。HCI開始、advertising、
connection complete、複数のGATT discovery resultが連続すると、新eventが旧eventを上書きし、
次の症状が発生する。

- HCI stateを失ってcentralが起動しない。
- Connection completeを失って接続待ちから進まない。
- Service resultを失って`service_not_found`になる。
- Query completeやnotificationを失ってreadyまたは表示更新へ進まない。

Event forwardingと保持は片方だけでは不十分なため、1個のruntime capabilityとして適用する。

## 詳細な技術的解説

### Central event forwarding

RP2040 portはroleがcentralのとき、次のeventを`BLE_push_event`へ渡す。

- `BTSTACK_EVENT_STATE`
- HCI working後の`HCI_EVENT_COMMAND_COMPLETE` / `HCI_EVENT_COMMAND_STATUS`
- `HCI_EVENT_DISCONNECTION_COMPLETE`
- `HCI_EVENT_LE_META` / `HCI_EVENT_META_GAP`
- Advertising report
- GATT query complete、service/characteristic/descriptor result、notification

`central_hci_working`はBLE roleの隣にある独立したstatic flagである。HCI初期化中の大量のcommand
eventは転送せず、`HCI_STATE_WORKING`以後にアプリが発行したscan/connect commandの結果だけを
Rubyへ渡す。

Ruby centralは標準LE Connection Complete、Enhanced Connection Complete v1/v2、BTstack GAP
LE Connection Completeを処理する。Disconnectはconnection handleに対応するslotだけをresetし、
もう一方のsensor接続を維持するために使う。

### mruby event queue

mruby版は次の固定長管理領域を持つ。

```c
#define BLE_EVENT_QUEUE_CAPACITY 8
static uint8_t *packet_queue[BLE_EVENT_QUEUE_CAPACITY];
static uint16_t packet_queue_size[BLE_EVENT_QUEUE_CAPACITY];
static uint8_t packet_queue_head;
static uint8_t packet_queue_count;
```

管理配列は50 bytesで、各payloadは`mrb_malloc`により実サイズ分だけ確保する。
`pop_packet`はheadからRuby Stringを作り、元bufferを解放してFIFO順に進める。GATT result、query
complete、notificationの相対順は維持される。

Queue途中のeventを削除するときはpayloadを解放し、後続pointerとsizeをring上で前へ詰め、tailを
`NULL`/0へ戻してcountを減らす。Capacityは8なのでshiftは最大7要素である。

### Queue満杯時の優先順位

非破棄eventとして明示的に保護するもの:

- `BTSTACK_EVENT_STATE`
- LE/GAPのconnection complete全形式
- `HCI_EVENT_COMMAND_STATUS`かつopcode `0x200d` (LE Create Connection)

破棄可能とするもの:

- GAPまたはLE Meta advertising report
- `0x200d`以外のcommand status
- すべてのcommand complete
- Size 0のevent

上記以外のdisconnect、GATT result、query complete、notificationも非破棄扱いである。満杯時は
次の順で空きを作る。

1. 新eventが破棄可能なら新eventを捨てる。
2. 新eventが非破棄ならqueue内で最初の破棄可能eventを削除する。
3. 8件すべてが非破棄なら最古eventを削除する。

したがって重要eventを絶対に失わない設計ではない。全8件がGATT/notification burstなら最古を
失う可能性がある。根拠なくcapacityを増やすのではなく、Ruby側sequence gapとheap余裕を実測する。

`0x200d`を保護する理由は、接続commandが非0 statusで失敗したときにpending slotを解除してscanへ
戻すためである。これをscan reportと同じ優先度で捨てると`connecting`状態が残り続ける。

### mruby/cを変更しない理由

共通`src/ble.c`の旧packet領域を`PICORB_VM_MRUBYC`条件内へ移し、mruby/cは従来どおり
single-packet bufferを使う。容量8 queueはPicoRuby/mruby host専用であり、FemtoRuby/mruby-cへ
同じ配送保証を追加するパッチではない。

### Ruby loopのbounded drain

Queueを空になるまで無制限に読むと、周囲のadvertisingが多い環境ではuser callbackへ戻れない。
`MultiUARTTransport`は1 tickで最大8 eventだけ処理し、20 ms単位でcallbackへ制御を返す。
Native queueとRuby側bounded drainは別のstarvation条件を解決するため、両方を維持する。

## 他に必要な説明事項

### 適用対象と順序

Host firmwareだけに適用し、notification listener patchの後、2 connection pool patchの前に置く。
Sensor firmwareには不要である。

### Memoryと診断

固定管理領域に加えて最大8 payload分をmruby heapから確保する。現在のhost no-display buildは
BSS 443,128 bytes、heap limitまで48,264 bytes、dual-display buildはBSS 444,748 bytes、
heap limitまで46,180 bytesの余裕がある。Patch自体はnative drop counterを公開しないため、
現在は`reader_gap_count`、接続state、NoMemoryErrorを観測する。

### 検証方法

- `scripts/verify_picoruby_patches.sh host`でpinned clean treeへの適用を確認する。
- CRuby testで非0の`0x200d` command statusからscanへ戻ることを確認する。
- Scan report flood中も20 ms callbackと定期status出力が継続することを確認する。
- 実機で片側disconnect後に他方の受信を維持し、切断slotだけ再scanすることを確認する。
- 2sensorを250 ms周期で受信し、`reader_gap_count`とheapを長時間観測する。

Queue満杯時のnative優先度は、今後BTstack event注入用test harnessを用意し、advertising report
8件でqueueを満たした後に`0x200d` command statusを投入して、scan reportが1件押し出され
command statusが`pop_packet`から取得できることを自動検証する。Production APIへevent注入methodは
追加せず、host-native test buildだけで`BLE_push_event`/`pop_packet`を直接検査する方針とする。

検証基準はPicoRuby `b0c1c4828b82b267dab9cabf4a372c46c2a1075e`、Pico SDK 2.2.0である。
BTstack更新時はevent type、subevent、opcode offsetを再確認する。

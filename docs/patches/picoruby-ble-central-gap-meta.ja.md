# picoruby-ble-central-gap-meta.patch

対象パッチ: [`patches/picoruby-ble-central-gap-meta.patch`](../../patches/picoruby-ble-central-gap-meta.patch)

## パッチの概要

RP2040/RP2350向けPicoRuby BLE portのcentral event forwardingを拡張し、Ruby側の
connection state machineに必要なHCI/GAP eventを`BLE_push_event`へ渡すパッチである。

主な変更は次のとおり。

- `HCI_EVENT_META_GAP`をRubyへ転送する。
- `HCI_EVENT_DISCONNECTION_COMPLETE`をRubyへ転送する。
- `HCI_EVENT_COMMAND_COMPLETE`と`HCI_EVENT_COMMAND_STATUS`をHCI working後だけ転送する。
- `BTSTACK_EVENT_STATE`からcentral HCIのworking状態を記録する。
- 既存の`HCI_EVENT_LE_META`、advertising、GATT event forwardingは維持する。

変更対象は次の1ファイルである。

```text
mrbgems/picoruby-ble/ports/rp2040/ble.c
```

## 必要な理由

Pico 2 W上のBTstackでは、LE connection completeが常に同じ形式だけで通知されるとは
限らない。実機ではBTstack固有の`HCI_EVENT_META_GAP`、subevent
`GAP_SUBEVENT_LE_CONNECTION_COMPLETE`としてconnection handleが届く場合があった。

元のcentral packet handlerは`HCI_EVENT_LE_META`を転送するが、
`HCI_EVENT_META_GAP`を転送しない。その場合、controller側では接続済みでもRuby側が
connection completeを受け取れず、次の状態で停止する。

```text
gap_connect
0
scan_state
TC_W4_CONNECT
```

また、disconnect eventが転送されなければslotをresetして再scanできない。Create
Connection command自体が失敗した場合も、command statusをRubyへ渡さなければpending
stateから回復できない。

## 詳細な技術的解説

### BTSTACK_EVENT_STATEの扱い

パッチはcentral専用のstatic flagを追加する。

```c
static bool central_hci_working = false;
```

`BTSTACK_EVENT_STATE`を受けるたびに、stateが`HCI_STATE_WORKING`なら`true`、それ以外なら
`false`にする。State event自体は常に`BLE_push_event`へ渡すため、Ruby側はHCI開始を
検出できる。

### Command eventをworking後に限定する理由

HCI初期化中は多数の`HCI_EVENT_COMMAND_COMPLETE` / `HCI_EVENT_COMMAND_STATUS`が発生する。
これらを起動直後からすべてRubyへ渡すと、容量の小さいevent queueを埋め、重要な
`BTSTACK_EVENT_STATE`を処理する前に遅延または上書きさせる可能性がある。

そこでcommand eventは`central_hci_working`がtrueのときだけ転送する。アプリがscanや
connectを開始した後のcommand結果は取得しつつ、controller初期化中のnoiseは抑える。

Ruby側ではopcodeも確認する。例えばLE Create Connectionは`0x200d`であり、このcommandの
statusが非0ならpending slotをresetしてscanへ戻す。

### Connection completeの複数形式

Ruby centralは少なくとも次を処理する。

| Event | Subevent |
| --- | --- |
| `HCI_EVENT_LE_META` | LE Connection Complete `0x01` |
| `HCI_EVENT_LE_META` | Enhanced Connection Complete v1 `0x0a` |
| `HCI_EVENT_LE_META` | Enhanced Connection Complete v2 `0x29` |
| `HCI_EVENT_META_GAP` | GAP LE Connection Complete `0x08` |

BTstackやcontrollerの経路によっては同じ接続に関係するeventが複数見えるため、Ruby側は
`pending_slot`の有無やstateを確認し、同じconnection completeを二重処理しない設計にする。

### Disconnectの配送

`HCI_EVENT_DISCONNECTION_COMPLETE`を転送することで、Ruby側はevent内のconnection handleを
使って該当slotだけをresetできる。2接続構成では、片方の切断時にもう片方の推定値と
notification listenerを維持するために必要である。

## 他に必要な説明事項

### このパッチが行わないこと

このパッチはeventをRuby queueへ渡すだけで、packet layoutの解析、state遷移、再scanは
実装しない。`BLECycleHost::MultiUARTCentral`または単一接続用runtime patchが、各eventを
解析する必要がある。

### 適用順と依存関係

現在のdiff contextは次の順を前提にしている。

```text
picoruby-ble-central-notification-listener.patch
picoruby-ble-all-notifications.patch
picoruby-ble-central-gap-meta.patch
picoruby-ble-preserve-state-event.patch
```

特に`ports/rp2040/ble.c`のstatic notification変数を含む状態へ適用するため、
all-notifications patchより先に適用するとcontextが一致しない可能性がある。

### Event queueとの関係

転送対象を増やすため、このパッチ単独では元のsingle-packet bufferでevent上書きを増やす
可能性がある。後続の`picoruby-ble-preserve-state-event.patch`を組み合わせ、重要eventを
小さなqueueで保持する。

### 検証方法

正常時は次の遷移を確認する。

```text
connecting_role
speed
connected_role
speed
connection_handle
64
```

片側sensorを再起動し、`disconnected_role`の後にscanが再開することも確認する。Command
failureを再現した場合は、非0 statusからpending stateが解除されることを確認する。

検証基準はPicoRuby
`b0c1c4828b82b267dab9cabf4a372c46c2a1075e`である。BTstack更新時はevent typeとoffsetを
再確認する。

# picoruby-ble-notification-listeners.patch

対象パッチ: [`patches/picoruby-ble-notification-listeners.patch`](../../patches/picoruby-ble-notification-listeners.patch)

## パッチの概要

PicoRubyのBLE centralへ、BTstackのnotification listenerを登録する3個のRuby APIを追加する。

```ruby
listen_for_characteristic_value_updates(connection_handle, value_handle)
listen_for_all_characteristic_value_updates
stop_listening_for_all_characteristic_value_updates
```

前者は特定connectionと特定characteristicを購読する単一接続向けAPI、後者2個は全connectionと
全characteristicを1個のlistenerで購読・停止する複数接続向けAPIである。C API、RP2040 port、
mruby/mruby-c binding、RBSを同じパッチで更新する。

このパッチは、旧`picoruby-ble-central-notification-listener.patch`と
`picoruby-ble-all-notifications.patch`を意味論的に統合したものである。Pinned revision上の
combined diffは旧2本と完全に一致し、APIや実行時動作は変更していない。

## 必要な理由

BLE peripheralのCCCDへ`0x0001`を書くだけでは、central側BTstackのcallback登録は行われない。
元のPicoRuby centralにはdiscoveryとCCCD writeはあるが、
`gatt_client_listen_for_characteristic_value_updates`を呼ぶRuby APIがない。そのため、sensor側で
`Notifications enabled`と`TX`が継続してもhost側へ`GATT_EVENT_NOTIFICATION`が届かなかった。

また、specific listenerはstatic 1枠であり、別connectionへ再登録すると以前の購読を停止する。
Speed sensorとcadence sensorを同時に受信するhostには、1個のlistenerで全connectionを受け、
Ruby側でconnection handleごとに配送するwildcard APIが必要になる。

## 詳細な技術的解説

### Specific listener

RP2040 portはBTstackが登録後も参照する構造体をfile scopeのstatic領域に保持する。

```c
static gatt_client_notification_t notification_listener;
static gatt_client_characteristic_t notification_characteristic;
```

Rubyから受けたvalue handleをcharacteristicへ設定し、以前のspecific listenerを停止してから
新しいconnectionへ登録する。このAPIで同時に購読できるのは1 connectionだけである。

### Wildcard listener

複数接続では次の条件でlistenerを1回だけ登録する。

```c
GATT_CLIENT_ANY_CONNECTION
NULL /* all characteristics */
```

`all_notification_listener_registered`で二重登録を防ぎ、停止APIでBTstackからlistenerを外して
flagを戻す。Connectionごとのlistener配列を追加しないため、接続数に比例するstatic RAMを
notification layerへ持ち込まない。

### CCCDとlistenerの関係

Wildcard listenerもCCCDを自動設定しない。各connectionでGATT discoveryを完了し、それぞれの
CCCDへ`"\x01\x00"`を書く必要がある。Listener登録はcentral内のevent配送設定、CCCD writeは
peripheralの送信許可であり、両方が必要である。

単一接続では通常、TX value handleとCCCD handleを確定した後に次の順で実行する。

```ruby
ble.listen_for_characteristic_value_updates(conn_handle, tx_handle)
ble.write_characteristic_descriptor_using_descriptor_handle(
  conn_handle,
  cccd_handle,
  "\x01\x00"
)
```

複数接続ではhost起動時にwildcard listenerを1回登録し、CCCD writeだけを各slotで行う。

### Ruby側の配送

Wildcard listenerは対象外characteristicも受けるため、Ruby側で次を検査する。

1. Event typeが`GATT_EVENT_NOTIFICATION`である。
2. Connection handleに対応するsensor slotが存在する。
3. Eventのvalue handleが、そのslotでdiscoveryしたTX handleと一致する。
4. Payload長がprotocolの期待値と一致する。

Pinned BTstackのevent layoutではconnection handleはoffset 2、value handleはoffset 8、value
lengthはoffset 10、payloadはoffset 12から始まる。Speed/cadenceが同じGATT databaseを使うと
value handleも同じになり得るため、value handleだけでroleを決めてはならない。

### Bindingと戻り値

Specific APIは2個のInteger、wildcard APIは引数なしとしてmrubyとmruby/cの両方で検査する。
RBSにも3 methodを`Integer`戻り値で宣言する。現在のC APIは登録処理を受理すると`0`を返すが、
これはCCCD設定やnotification受信まで保証する値ではない。

### Listenerの併用制約

Specific listenerとwildcard listenerは別のBTstack listenerとして存在する。同時に登録すると、
同じnotificationが2回Rubyへ配送される可能性がある。Runtimeでは次のどちらか一方だけを使う。

- Legacy単一接続`UARTCentral`: specific listener。
- 2sensor `MultiUARTCentral`: wildcard listener。

## 他に必要な説明事項

### 適用対象と順序

Host firmwareだけに適用する。Sensor peripheralには不要である。現行host patch chainでは
passive scanの後、central event deliveryの前に適用する。

```text
1. picoruby-ble-passive-scan.patch
2. picoruby-ble-notification-listeners.patch
3. picoruby-ble-central-event-delivery.patch
4. picoruby-ble-two-connections.patch
5. picoruby-gc9a01-speedometer.patch       # display buildだけ
```

Wildcard登録flagとBTstackの実状態がずれないよう、BLE owner終了時には停止APIを呼ぶ。HCIを
外部からpower cycleする場合も停止・再登録を同じlifecycleで行う。

### 検証方法

- `scripts/verify_picoruby_patches.sh host`でclean適用を確認する。
- Host ELFにwildcard listenerの開始・停止symbolがあることを確認する。
- Legacy hostで`listen_notifications 0`の後に`RX`が継続することを確認する。
- 2sensor hostで異なるconnection handleから同じvalue handleが届いても別slotへ配送されることを
  確認する。
- 片方のCCCD設定後も、もう片方のnotificationが停止しないことを確認する。

検証基準はPicoRuby `b0c1c4828b82b267dab9cabf4a372c46c2a1075e`、Pico SDK 2.2.0である。
別revisionではupstreamに同等APIが追加されていないかを先に確認する。

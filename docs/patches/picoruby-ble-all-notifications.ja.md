# picoruby-ble-all-notifications.patch

対象パッチ: [`patches/picoruby-ble-all-notifications.patch`](../../patches/picoruby-ble-all-notifications.patch)

## パッチの概要

全BLE connection、全characteristicを対象にするBTstack notification listenerを1個登録し、
Ruby側でconnection handleとvalue handleを使って配送できるようにするパッチである。

追加されるRuby APIは次の2個である。

```ruby
ble.listen_for_all_characteristic_value_updates
ble.stop_listening_for_all_characteristic_value_updates
```

どちらも引数なしで、成功時は`0`を返す。mruby、mruby/c、RBS、RP2040 portのC APIを
同時に追加する。

## 必要な理由

Speed sensorとcadence sensorは同じcustom service/characteristic定義を使うため、両方の
GATT value handleが同じ値になることがある。通知元をvalue handleだけで識別することは
できず、connection handleも必要になる。

また、`picoruby-ble-central-notification-listener.patch`のlistenerはstatic 1slotであり、
再登録すると前のconnectionのlistenerを停止する。2台目を購読した時点で1台目の通知を
受けられなくなるため、2接続構成にはそのまま利用できない。

本パッチはBTstackが提供するwildcard指定を使い、1個のlistenerで全connectionの
notification eventを受ける。Ruby側の`MultiUARTCentral`はevent内のconnection handleで
speed/cadence slotを選び、さらにslotごとのTX value handleを照合する。

## 詳細な技術的解説

### BTstackのwildcard listener

登録時に次の2値を指定する。

```c
GATT_CLIENT_ANY_CONNECTION
NULL
```

BTstackでは`GATT_CLIENT_ANY_CONNECTION`が全connection、characteristicの`NULL`が
全characteristicを表す。これにより、接続ごとのlistener配列をC側に持たずに済む。

```c
gatt_client_listen_for_characteristic_value_updates(
  &all_notification_listener,
  &packet_handler,
  GATT_CLIENT_ANY_CONNECTION,
  NULL
);
```

### Static領域と二重登録防止

パッチは次のstatic状態を追加する。

```c
static gatt_client_notification_t all_notification_listener;
static bool all_notification_listener_registered = false;
```

登録済みなら再登録せず`0`を返す。停止APIは同じlistenerをBTstackから外し、flagを
`false`へ戻す。単一connection用の`notification_listener`とは別領域なので、後方互換の
APIを壊さない。

### CCCDはconnectionごとに必要

Wildcard listenerはcentral内部のevent配送範囲を広げるだけで、peripheralのCCCDを
自動設定しない。Speed/cadenceそれぞれについてGATT discoveryを行い、各connectionの
CCCDへ`0x0001`を書かなければならない。

### Ruby側で必要なfilter

Wildcard listenerは対象外characteristicのnotificationも受ける。Ruby側は少なくとも
次の順でfilterする必要がある。

1. Event typeが`GATT_EVENT_NOTIFICATION`か確認する。
2. Eventからconnection handleを取得する。
3. Connection handleに対応するslotを選ぶ。
4. Eventのvalue handleが、そのslotのTX handleと一致するか確認する。
5. Value lengthを検証してpayloadをdecoderへ渡す。

本プロジェクトのBTstack event parserはconnection handleをoffset 2、value handleを
offset 8、value lengthをoffset 10、payloadをoffset 12から読む。これは使用中のpinned
BTstack event layoutに依存するため、Pico SDK/BTstack更新時には再確認が必要である。

### API binding

mruby bindingは引数なしmethodを2個登録する。mruby/c bindingは`argc == 0`を検査し、
余分な引数があれば`ArgumentError`にする。RBSにも戻り値`Integer`として宣言する。

## 他に必要な説明事項

### 適用順と依存関係

必ず`picoruby-ble-central-notification-listener.patch`の後に適用する。さらに
`picoruby-ble-central-gap-meta.patch`は、このパッチ適用後の`ports/rp2040/ble.c`を
前提とするため、本パッチの後に適用する。

### Lifecycle

Host起動時、HCIがworkingになった後に1回登録する。アプリ終了時は
`stop_listening_for_all_characteristic_value_updates`を呼ぶ。本プロジェクトの
`MultiUARTCentral#start`は`ensure`で停止する。

Flagだけが登録状態を表すため、BTstackを外部からresetした場合はRuby側でも停止・再登録の
lifecycleを揃える必要がある。

### Event量とメモリ

Listener自体はstatic 1個で、connection数に比例したC側listener配列を追加しない。一方で
全characteristicを受けるため、接続先が増えるほどRuby event queueの流量は増える。
不要なnotificationをRuby側で早期に捨て、hot pathでHashや一時Arrayを生成しないことが
重要である。

### 検証方法

2台のsensorを接続し、次を確認する。

- 異なる2個のconnection handleがreadyになる。
- 同じTX value handleでもconnection handle別にspeed/cadenceへ配送される。
- 両sensorのsequenceが独立して増える。
- 片方のCCCD設定後も、もう片方のnotificationが止まらない。
- Listener停止後に不要なnotification callbackが継続しない。

このパッチはPicoRuby
`b0c1c4828b82b267dab9cabf4a372c46c2a1075e`と、そのPico SDK 2.2.0同梱BTstackで
検証している。

# picoruby-ble-central-notification-listener.patch

対象パッチ: [`patches/picoruby-ble-central-notification-listener.patch`](../../patches/picoruby-ble-central-notification-listener.patch)

## パッチの概要

BLE centralが特定connectionの特定characteristicについて、BTstackへnotification
listenerを登録するAPIをPicoRubyへ追加するパッチである。

追加されるRuby APIは次のとおり。

```ruby
result = ble.listen_for_characteristic_value_updates(
  connection_handle,
  value_handle
)
```

変更対象は次の5ファイルである。

| ファイル | 役割 |
| --- | --- |
| `mrbgems/picoruby-ble/include/ble.h` | C API宣言 |
| `mrbgems/picoruby-ble/ports/rp2040/ble.c` | BTstack listener本体 |
| `mrbgems/picoruby-ble/sig/ble.rbs` | Ruby API型定義 |
| `mrbgems/picoruby-ble/src/mruby/ble_central.c` | mruby binding |
| `mrbgems/picoruby-ble/src/mrubyc/ble_central.c` | mruby/c binding |

## 必要な理由

BLE notificationを受けるには、peripheral側CCCDへ`0x0001`を書くだけでは不十分である。
CCCD writeはperipheralへnotification送信を許可する操作であり、central内部のBTstackへ
どのvalue updateをcallbackするか登録する操作とは別である。

元のPicoRuby BLE central APIにはservice discovery、characteristic discovery、CCCD writeは
あるが、`gatt_client_listen_for_characteristic_value_updates`を呼ぶRuby APIがなかった。
この状態では次のような症状になる。

- GATT discoveryとCCCD writeは成功する。
- Sensor側には`Notifications enabled`が出る。
- Sensorは`TX`を継続する。
- Host側へ`GATT_EVENT_NOTIFICATION`が届かず、`RX`が出ない。

独自`BLE::UART`でsensor packetを受信するため、この欠けているlistener登録を追加する。

## 詳細な技術的解説

### Listener構造体の寿命

BTstackのlistener登録APIは、登録後も次の構造体を参照する。

```c
gatt_client_notification_t
gatt_client_characteristic_t
```

そのため関数内のstack変数にはできない。パッチはRP2040 portのfile scopeへ次のstatic
領域を追加する。

```c
static gatt_client_notification_t notification_listener;
static gatt_client_characteristic_t notification_characteristic;
```

Rubyから渡された`value_handle`を使い、characteristicの`start_handle`、
`value_handle`、`end_handle`を同じ値へ設定する。UUIDやpropertyはnotificationの
filterに不要なため0で初期化する。

### 再登録時の動作

新しいlistenerを登録する前に、同じstatic listenerについて次を呼ぶ。

```c
gatt_client_stop_listening_for_characteristic_value_updates(
  &notification_listener
);
```

その後、指定されたconnection/value handleでlistenerを登録する。これにより同じ領域を
再利用したまま登録先を切り替えられるが、同時に保持できるlistenerは1個だけである。

### Ruby binding

mruby bindingでは2個のIntegerを`mrb_get_args(..., "ii", ...)`で取得する。
mruby/c bindingでは引数数と型を明示検査する。どちらもC APIの戻り値をIntegerとして
Rubyへ返す。

現在のC APIはBTstack登録関数が`void`であるため、引数を受理して登録処理を行うと常に
`0`を返す。この`0`はlistenerが実際にnotificationを受信したことまでは保証しない。

### CCCDとの実行順

通常はGATT discoveryでTX value handleとCCCD handleを確定した後にlistenerを登録し、
対象connectionのCCCDへ`"\x01\x00"`を書く。

```ruby
ble.listen_for_characteristic_value_updates(conn_handle, tx_handle)
ble.write_characteristic_descriptor_using_descriptor_handle(
  conn_handle,
  cccd_handle,
  "\x01\x00"
)
```

Listener登録とCCCD writeの両方が揃って初めて、centralはnotificationを継続受信できる。

## 他に必要な説明事項

### 単一listenerという制約

再登録時に以前のlistenerを停止するため、このAPI単独では2台のsensorを同時購読できない。
2接続hostでは次の`picoruby-ble-all-notifications.patch`が追加するwildcard listenerを使う。

### 適用順

`picoruby-ble-all-notifications.patch`の前に適用する。後者のdiffは、このパッチが追加した
C API、static変数、mruby/mruby-c bindingを前提に作られている。

### 適用対象

- 単一sensor host: このパッチのAPIを直接使用できる。
- 2sensor host: 後続のall-notifications patchの土台として必要である。
- BLE peripheral sensor: listenerを使わないため不要である。

### 検証方法

Hostで次を確認する。

```text
listen_notifications
0
NUS central ready
RX
```

Sensor側では`Notifications enabled`と`TX`が継続することを確認する。CCCD有効化だけ成功し
Hostに`RX`がなければ、listener登録APIを含むUF2か、notification eventのpacket offsetを
確認する。

このパッチはPicoRuby
`b0c1c4828b82b267dab9cabf4a372c46c2a1075e`向けpatch chainで検証している。

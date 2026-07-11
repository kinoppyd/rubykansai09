# BLE::UARTによる2センサ同時接続の実現性調査

最終更新: 2026-07-11 JST

## 調査目的

Raspberry Pi Pico 2 Wを3台使い、次の構成を実現できるか調査した。

- スピードセンサ: Pico 2 W + MPU-6050
- ケイデンスセンサ: Pico 2 W + MPU-6050
- ホスト/表示: Pico 2 W + 2台のGC9A01
- 各センサの通知周期: 500 ms
- 通信方式: 独自UUIDの`BLE::UART`
- 規格方針: CSCS/CSCPは使用しない

既存システムでは、スピードセンサ1台から20-byte固定frameを受信し、速度を
GC9A01へ表示できている。今回の焦点は、同じホストが既存接続を維持したまま
2台目のケイデンスセンサへ接続し、両方のnotificationを混線せず処理できるかである。

実装手順は[CADENCE_TODO.md](../../CADENCE_TODO.md)に分離している。本資料は、
採用方針を決めた根拠と技術的制約を記録する。

## 結論

Pico 2 WのhardwareとBTstackは、スピードセンサとケイデンスセンサの2接続を
同時に維持できる可能性が十分にある。500 msごとに20 bytesを2台から受信する
用途では、BLE帯域も問題にならない。

ただし、現在のPicoRuby `BLE::UART`を2instance生成するだけでは実現できない。
PicoRuby native層と`BLE::UART`のrun loopがBLE stack全体を単一ownerとして扱って
いるためである。

採用する方針は次のとおり。

1. 独自`BLE::UART` serviceと20-byte payload v1は維持する。
2. Host firmwareだけBTstackのHCI connectionとGATT clientを2slotへ増やす。
3. `BLE::UART`は1instanceだけ生成する。
4. その1instanceを所有する固定2slotのmulti-central managerを追加する。
5. Eventをconnection handleでspeed/cadence slotへ配送する。
6. 接続とGATT discoveryは逐次実行し、確立済み接続は維持する。
7. 実機で不安定な場合は、CSCSではなくnative独自GATT centralへ移行する。

| 構成 | 判定 | 理由 |
| --- | --- | --- |
| 現行UF2 + 現行`BLE::UART` | 不可 | HCI/GATT slotが1、central stateも1接続分だけ |
| `BLE::UART`を2instance生成 | 不可 | Native global stateとevent queueを共有する |
| Host設定を2slot化しただけ | 不十分 | Notification listenerとRuby state machineが単一接続前提 |
| 1 BLE owner + 固定2slot manager | 実現可能性が高い | BTstackのconnection handle別APIを利用できる |
| Native独自GATT central | 実現可能性が最も高い | Ruby objectとevent routingを最小化できる |

## 調査環境

ローカル調査に使用したversionは次のとおり。

| Component | Revision |
| --- | --- |
| このrepository | `dae145836bd535e4bd6a9fd8207b9cecfc4c47ba` |
| PicoRuby checkout | `b0c1c4828b82b267dab9cabf4a372c46c2a1075e` |
| Pico SDK | `a1438dff1d38bd9c65dbd693f0e5db4b9ae91779`、version 2.2.0 |
| BTstack submodule | `501e6d2b86e6c92bfb9c390bcf55709938e25ac1`、v1.6.2系 |
| Target | Raspberry Pi Pico 2 W、RP2350 Arm secure build |

2026-07-11時点のPicoRuby upstream master
`7869bc06d0c610a9c702c416df81c9a38267b55b`も確認した。BLE connection数と
`BLE::UART`の単一接続構造は、上記local checkoutから変わっていなかった。

このrepositoryには、upstreamにない次のBLE patchがある。

- [Passive scan patch](../../patches/picoruby-ble-passive-scan.patch)
- [GAP meta event patch](../../patches/picoruby-ble-central-gap-meta.patch)
- [Event queue patch](../../patches/picoruby-ble-preserve-state-event.patch)
- [Notification listener patch](../../patches/picoruby-ble-central-notification-listener.patch)

以下の判断は、upstreamの制約だけでなく、これらを適用した現在の実機動作版を
前提にしている。

## HardwareとPico SDK

Pico 2 WはRP2350とInfineon CYW43439を搭載し、Pico SDKはCYW43 HCI transport上で
BlueKitchen BTstackを動かす。Bluetooth処理はBTstackの単一run loopへ統合される。

Raspberry Pi側の説明では、同時BLE接続数はBTstack設定とCYW43439 controllerの
小さい方で制限される。BTstack側はおおむね次の設定値で決まる。

```c
min(MAX_NR_HCI_CONNECTIONS, MAX_NR_GATT_CLIENTS)
```

設定値はapplication側の`btstack_config.h`で増やせる。CYW43439側にはconnection
parameterとcontroller内部memoryに基づく上限があるが、公開資料には明確な固定値が
ない。したがって、2接続が安定するかは最終的に実機で確認する必要がある。

今回の用途は2接続だけであり、各linkのapplication notificationは2 Hzである。
高スループット用途と比べてradio schedulingの条件は緩いと推測できる。ただし、
1本目を維持しながらscanと2本目のconnectを行う部分は個別に検証する。

参考:

- [Raspberry Pi Pico SDK networking libraries](https://www.raspberrypi.com/documentation/pico-sdk/networking.html)
- [Raspberry Pi concurrent BLE connection discussion](https://github.com/raspberrypi/pico-feedback/issues/313)
- [Infineon CYW43439 product brief](https://www.infineon.com/assets/row/public/documents/30/45/infineon-wifi-cyw43439-productbrief-en.pdf)

## BTstackの接続数とmemory model

PicoRubyの`btstack_config.h`は次の設定になっている。

```c
#define MAX_NR_GATT_CLIENTS 1
#define HCI_ACL_PAYLOAD_SIZE (255 + 4)
#define MAX_NR_HCI_CONNECTIONS 1
```

BTstackは`HAVE_MALLOC`を使わない構成では、各種connection objectをcompile時の
固定poolへ確保する。`MAX_NR_HCI_CONNECTIONS`と`MAX_NR_GATT_CLIENTS`を増やすと、
対応する固定poolがBSS上で増える。

BTstackのGATT clientはconnection handleごとにcontextを持つため、2slotを確保すれば
異なる2接続でGATT queryを扱える。Notification listener APIも次をサポートしている。

- 特定connection handleだけをlistenする。
- `GATT_CLIENT_ANY_CONNECTION`ですべてのconnectionをlistenする。
- 特定characteristicを指定する。
- Characteristicに`NULL`を渡してすべてのcharacteristicをlistenする。

したがって、BTstack本体には今回必要なevent routing機能がある。制約は主に
PicoRuby bindingとRuby state machineにある。

参考:

- [BTstack configuration and memory directives](https://bluekitchen-gmbh.com/btstack/how_to.html)
- [BTstack GATT client header](https://github.com/bluekitchen/btstack/blob/master/src/ble/gatt_client.h)
- [PicoRuby btstack_config.h](https://github.com/picoruby/picoruby/blob/7869bc06d0c610a9c702c416df81c9a38267b55b/mrbgems/picoruby-ble/include/btstack_config.h)

## PicoRuby native BLE層の制約

PicoRubyのRP2040/RP2350 BLE portは、BLE stack全体に対して次のstatic stateを持つ。

- 現在のBLE role
- HCI event callback registration
- Security Manager event callback registration
- heartbeat timer
- BTstack packet handler
- Ruby VMへのevent queue
- ATT read/write value storage

`BLE#initialize`から呼ばれるnative `_init`は、instance専用contextを作るのではなく、
`l2cap_init`、`sm_init`、`gatt_client_init`とglobal callback登録を行う。またmruby binding
ではglobalな`write_values` / `read_values` Hashも再作成する。

このため、同じVMで次のように2instanceを生成する方法は安全ではない。

```ruby
speed_uart = BLE::UART.new(role: :central, ...)
cadence_uart = BLE::UART.new(role: :central, ...)
```

2回目の初期化はBLE stackをinstance単位で追加するのではなく、共有状態を再初期化する。
さらに2instanceは同じ`pop_packet`からeventを取得するため、どちらがeventを消費するか
保証できない。

Upstream mruby bindingは最新masterでもpacket 1個だけを保持する。現在のrepositoryでは
重要eventを失わないよう8要素queueへpatchしているが、queue自体は依然としてglobalで
ある。

参考:

- [PicoRuby RP2040 BLE port](https://github.com/picoruby/picoruby/blob/7869bc06d0c610a9c702c416df81c9a38267b55b/mrbgems/picoruby-ble/ports/rp2040/ble.c)
- [PicoRuby mruby BLE binding](https://github.com/picoruby/picoruby/blob/7869bc06d0c610a9c702c416df81c9a38267b55b/mrbgems/picoruby-ble/src/mruby/ble.c)

## BLE::UART Ruby層の制約

`BLE::UART` centralは1instance内に次の単一接続用stateを持つ。

- `@uart_central_state`
- `@conn_handle`
- `@peer_rx_handle`
- `@peer_tx_handle`
- `@peer_cccd_handle`
- `@nus_start_handle` / `@nus_end_handle`
- `@rx_buffer` / `@tx_buffer`
- `@connected`

`BLE::UART#start`はHCIをpower onし、共有packetをpollするblocking loopである。終了時には
HCIをpower offする。このため、2個の`start` loopを並行して動かす設計にはなっていない。

現在のcycle hostも[UARTCentral](../../lib/ble_cycle_host/uart_central.rb)が1個の
`BLE::UART`を所有し、[runtime central patch](../../lib/ble_cycle_host/uart_central_patch.rb)
が単一state machineを上書きしている。

複数接続では、`@conn_handle`などを単純なArrayに変えるだけでは足りない。Scan、
pending connect、GATT discovery、CCCD write、ready、disconnectをslotごとに管理し、
eventのconnection handleから対象slotを決める必要がある。

参考:

- [PicoRuby BLE::UART implementation](https://github.com/picoruby/picoruby/blob/7869bc06d0c610a9c702c416df81c9a38267b55b/mrbgems/picoruby-ble-uart/mrblib/ble_uart.rb)

## 現行notification listener patchの制約

[Notification listener patch](../../patches/picoruby-ble-central-notification-listener.patch)
は、notificationをRuby packet handlerへ配送するために次の2個をstaticに持つ。

```c
static gatt_client_notification_t notification_listener;
static gatt_client_characteristic_t notification_characteristic;
```

登録関数は毎回次の処理をする。

1. `notification_characteristic`を今回のvalue handleで上書きする。
2. 既存`notification_listener`をstopする。
3. 今回のconnectionだけをlistenする。

2台目へ登録すると1台目のlistenerが解除されるため、現状のままでは2台同時受信できない。

第一候補は、persistent listenerを1回だけ次の条件で登録する方法である。

```text
connection = GATT_CLIENT_ANY_CONNECTION
characteristic = NULL
```

各connectionのCCCDは個別に有効化し、届いたnotification eventのconnection handleと
value handleをRuby側へ渡す。同じGATT databaseを使う2sensorではvalue handleも同じに
なる可能性が高いため、value handleだけでroleを決めてはならない。

Pinned BTstackでwildcard listenerが安定しない場合は、固定2要素のlistenerと
characteristic配列をC側に持つ。動的allocationは不要である。

## Event queueの制約

現在の[event queue patch](../../patches/picoruby-ble-preserve-state-event.patch)は、
mruby heapからevent packet分をallocateする8要素queueである。Queueが満杯の場合は
scan reportやcommand statusなどを優先して破棄し、BTstack stateとconnection completeを
残す。

2接続化で注意するeventは次のとおり。

- 1本目を維持した状態で大量に届くscan report
- 2本目のconnection complete
- GATT service/characteristic query result
- 2接続から交互に届くnotification
- 片側のdisconnection complete

2sensorのnotificationは合計4 event/sなので、100 msごとにqueueを全drainする現在の
loopなら定常状態の負荷は低い。接続中のscan report burstが主なリスクである。

初期実装ではqueue容量を8のままにし、次を追加して判断する。

- Event type別drop counter
- 最大queue depth
- Notification drop counter
- Connection/GATT critical event drop counter

容量を先に増やすとheap消費とfragmentationの原因が見えにくくなるため、実測後にだけ
変更する。

## 通信帯域

Application payloadだけを計算すると次のとおり。

```text
20 bytes/frame * 2 frames/s * 2 sensors = 80 bytes/s
```

BLE link layer、ATT、HCIのheaderやretransmissionはこの値に含まれない。それでも
今回のデータ量はBLEの通常の転送能力より十分小さい。500 msの更新周期を維持できない
場合は、帯域よりevent loss、Ruby loop latency、radio scheduling、connection stateの
不具合を先に疑う。

## 2接続設定のbuild計測

既存のBLE + dual GC9A01統合build treeで、次の2行だけを一時的に`1`から`2`へ変更した。

```c
#define MAX_NR_GATT_CLIENTS 2
#define MAX_NR_HCI_CONNECTIONS 2
```

Incremental build:

```sh
cmake --build build/r2p2/picoruby/pico2_w/prod --parallel 8
```

Linkは成功した。`arm-none-eabi-size`とlink mapの比較結果は次のとおり。

| Item | 1 connection | 2 connections | Difference |
| --- | ---: | ---: | ---: |
| text | 2353748 | 2353748 | 0 |
| data | 0 | 0 | 0 |
| BSS | 443832 | 444736 | +904 |
| Heap limitまでの空き | 47096 | 46192 | -904 |
| Stack予約 | 8192 | 8192 | 0 |

2接続時のlink map:

```text
gatt_client_storage   0x120 = 288 bytes for 2 slots
hci_connection_storage 0x5f0 = 1520 bytes for 2 slots
__bss_end__           0x20072b90
__HeapLimit           0x2007e000
```

1slotあたりの増加は次の内訳になる。

```text
GATT client:    144 bytes
HCI connection: 760 bytes
Total:          904 bytes
```

この計測から、BTstack固定poolの2slot化自体はmemory上のblockerではない。ただし、
2個目のRuby slot、FrameReader、Decoded packet、受信String、event queue allocationを
含めたruntime stabilityは証明していない。

計測後、検証用sourceの設定は`1`へ戻した。このbuildで生成されたUF2は実機配布用ではない。

## 推奨multi-central設計

### 全体構成

```text
                         +----------------------+
Speed sensor ----------> |                      | ---> SpeedEstimator
  BLE Peripheral         | MultiUARTCentral     |
                         | one BLE::UART owner  |
Cadence sensor --------> | two fixed slots      | ---> CadenceEstimator
  BLE Peripheral         +----------------------+
                                    |
                                    v
                         dual GC9A01 display output
```

`BLE::UART` ownerは1個だけにし、そのownerがglobal event queueをすべてdrainする。
Speed/cadence slotはeventを受け取る状態containerであり、個別のBLE instanceではない。

### Slot state

各slotが保持する最小状態は次のとおり。

- Sensor role
- Hardcodeしたtarget address
- 補助的なtarget name
- Connection handle
- Connection/discovery state
- Service start/end handle
- Peer RX/TX/CCCD handle
- `BLECyclePacket::FrameReader`
- 再利用する`BLECyclePacket::Decoded`
- Last sequence、gap count、dropped bytes
- Last packet timeとtimeout state

Hot pathでpacketごとのHashやArrayを生成しない。2slotは固定長にして、sensor追加UIや
動的なslot管理は後続taskへ分ける。

### Connection state machine

初期接続は逐次実行する。

```text
HCI working
  -> scan missing sensor
  -> connect slot A
  -> discover service A
  -> discover characteristics A
  -> write CCCD A
  -> slot A ready
  -> resume scan while A remains connected
  -> connect slot B
  -> discover/subscribe B
  -> both ready
```

同時に2個の`gap_connect`を発行しない。初期実装ではGATT discoveryも1slotずつ行う。
これにより、query resultの対象はactive discovery slotで判断できる。一方、ready済み
slotから届くnotificationは、discovery中でもconnection handleで処理する。

### Event routing

| Event | Routing key |
| --- | --- |
| Advertising report | Target address、補助的にname/service UUID |
| Connection complete | Pending connect slot + new connection handle |
| GATT query result | Active discovery slot |
| Notification | Connection handle + value handle |
| Disconnection complete | Disconnected connection handle |

GATT eventのbyte offsetは、upstream eventとこのrepositoryのGAP meta forwardingで差が
生じた経緯がある。実装時はsynthetic packet testを追加し、可能な箇所はC側のBTstack
getterでconnection handleを抽出する。

### Reconnection

片側切断時にglobal resetを行ってはならない。

1. Disconnection handleから対象slotを見つける。
2. そのslotだけのconnection/GATT handleとFrameReader partial dataをclearする。
3. 他方のslotと推定値は維持する。
4. Missing slotを対象にscanを再開する。
5. 再接続後にそのslotだけGATT discoveryとCCCD writeを行う。

Speed sensor再接続中もcadenceを更新し、cadence sensor再接続中もspeedを更新する。

## Sensor identityとadvertising size

初期実装ではpayload v1を変更せず、hardcodeしたBLE addressでroleを決める。

| Role | Initial name | Identification |
| --- | --- | --- |
| Speed | `PRCycle` | Existing speed address |
| Cadence | `PRCad` | New cadence address |

Legacy advertisingは最大31 bytesである。現在と同じflags、local name、128-bit service
UUIDを入れる場合のおおよその内訳は次のとおり。

```text
Flags AD structure:       3 bytes
Local name AD structure:  2 + N bytes
128-bit UUID AD structure: 18 bytes
Total:                    23 + N bytes
```

したがってcomplete local nameは8 bytes以下にする。`PRCad`は5 bytesなので収まる。
長い`PRCadence`は9 bytesで、同じadvertising構成では31-byte上限を超える。

同じ独自service/RX/TX UUIDを両sensorで使ってよい。Roleはaddressとslotで既知なので、
初期実装でpayloadにrole byteを追加する必要はない。将来address固定を外す段階で
payload v2を検討する。

Hardcodeしたaddressは接続先選択にすぎず、認証や暗号化を保証しない。実験用途で
許容し、security requirementは別taskとする。

## Cadence計算

Cadence sensorをクランクへ取り付け、1回転を1 pedal revolutionとして扱う。

```text
rotations = delta_angle_mrad / 1000.0 / (2 * PI)
cadence_rpm = abs(rotations) * 60000.0 / interval_ms
```

Speed sensorのwheel回転をcadenceとして使わない。Hostには独立した
`CadenceEstimator`を追加し、次をspeed estimatorと別に管理する。

- Current cadence rpm
- Last update time
- Stop/timeout state
- Sequence gap
- Zero-delta count

First packetまたは`interval_ms <= 0`では0 rpmとする。初期値は逆回転も絶対値表示に
し、timeoutは既存speedと同じ1500 msを使用する。

## Runtime memory方針

2接続設定後のlink map上のheap余裕は約46 KiBである。静的pool追加は小さいが、
PicoRuby runtimeでは次を抑える必要がある。

- PacketごとのHash/Array生成
- Role名やaddressの繰り返しString生成
- 無制限に伸びる`@rx_buffer`
- Scan reportごとの詳細log
- Event packetの長期保持
- 2slot間で共有できない不要なparser object

一方、次はslotごとに分ける必要がある。

- FrameReader buffer
- Decoded packet instance
- Partial frame state
- Sequence/gap counter
- Last update time

GC9A01実装はfull framebufferを持たないため、2画面化で大きなframebuffer allocationは
発生しない。それでもBLE + mruby + 2画面の統合実機で30分以上のheap安定性を確認する。

## 実機で未確認の項目

今回確認できたのはsource調査と2slot設定のbuild/linkまでである。次は未確認である。

- CYW43439で2本のBLE connectionを実際に同時維持できるか。
- 1本目接続中にpassive scanと2本目のconnectが成功するか。
- 2connection分のGATT client contextが正しく生成されるか。
- Wildcard notification listenerがpinned BTstackで両linkを配送するか。
- Ruby event queueがscan burst中にcritical eventを失わないか。
- 2sensorが500 ms周期を長時間維持できるか。
- 片側だけのpower cycleと再接続が他方へ影響しないか。
- BLE + dual GC9A01でNoMemoryErrorが発生しないか。

これらは実装後、次の順に確認する。

1. 新host firmware + speed sensor 1台の回帰。
2. Cadence sensor 1台だけのfake notification。
3. Speed real + cadence fake。
4. Speed fake + cadence real。
5. Speed real + cadence real。
6. 片側ずつのpower cycle。
7. 起動順を変えた再接続。
8. 30分、可能なら2時間の連続試験。

## 主なriskと対策

| Risk | 初期対策 | Escalation |
| --- | --- | --- |
| 2本目のconnectが失敗 | Connect/discoveryを逐次化 | Connection parameterを調整 |
| Notificationが片側だけ届く | Wildcard listenerとhandle routing | 固定2listenerへ変更 |
| Scan中にevent queueが埋まる | Scan reportを優先破棄、drop計測 | Queue構造をnative固定buffer化 |
| 片側切断で両方reset | Slot単位reset | State machineをnativeへ移動 |
| Ruby heap不足 | 固定2slot、object再利用、log抑制 | Native独自GATT central |
| Radio scheduling不安定 | 50..100 ms connection intervalを試験 | Connectionless advertising |
| Sensor role混線 | Hardcode address + connection handle | Payload v2へrole追加 |

## 代替案

すべての代替案でCSCS/CSCPは使用しない。

### 1. Native独自GATT central

最優先fallbackである。既存と同じ独自UUID、TX notification、20-byte payloadを使い、
固定2slotのconnection/GATT state machineをC側へ実装する。Ruby側は次の最小APIだけを
pollする。

```text
available?(role)
read(role, buffer)
connected?(role)
state(role)
```

利点:

- Connection handle routingをBTstack getterで処理できる。
- Ruby event packet/String allocationを減らせる。
- Fixed bufferでmemory上限を決められる。
- 片側再接続のstateを厳密に管理できる。

欠点:

- Native patchの実装量とbuild検証が増える。
- PicoRuby upstream差分の保守が必要になる。

### 2. Connectionless custom advertising

各sensorが500 msごとにcustom manufacturer dataをadvertiseし、hostが常時scanする。
BLE connection、GATT discovery、CCCD、notification listenerが不要になる。

20-byte payloadにmanufacturer dataのoverheadとflagsを加えてもlegacy 31-byte advertisingへ
収められる。Nameと128-bit service UUIDは同じpacketに入れず、addressまたはpayload roleで
識別する。

利点:

- Connection数制約がない。
- Sensor追加が容易。
- Host state machineが単純になる。

欠点:

- ACKがなくpacket lossを許容する必要がある。
- 同じsampleを複数回advertiseするなどの補償が必要になる。
- Sequence gapとstale timeoutが必須になる。

### 3. Cadence専用receiver Picoを追加

Speed receiverとcadence receiverを分け、それぞれ現行の単一`BLE::UART`で接続する。
Cadence receiverから表示hostへUARTまたはI2Cでrpmを渡す。

利点:

- 現行`BLE::UART`をほぼ変更しない。
- Software riskが最小になる。

欠点:

- Pico 2 Wがもう1台必要になる。
- Wired interconnectとfailure stateが増える。

### 採用しない案

1台のhostがspeed/cadenceへ交互にconnect/disconnectする方式は採用しない。BLE connect、
GATT discovery、CCCD writeのlatencyと失敗回復が500 ms更新周期に対して大きく、既存接続を
維持する目的にも合わない。

## Go/No-Go判断

次を満たせば`BLE::UART` multi-central方式を継続する。

- 異なる2個のconnection handleが同時にreadyになる。
- 両sensorから450..650 ms程度でnotificationを受信できる。
- Value handleが同じでもconnection handleで正しくrole分離できる。
- 一方のpower cycle中も他方の受信が継続する。
- 30分試験でNoMemoryErrorと継続的なqueue dropがない。
- Speed/cadence表示が独立してtimeoutする。

次のいずれかが再現し、connection parameterやqueue優先度の調整でも解消しない場合は
native独自GATT centralへ移行する。

- 2本目のconnectionまたはGATT client contextを安定して確立できない。
- Notificationをconnection handle別に安定配送できない。
- Ruby event queue overflowまたはheap不足が継続する。
- 片側再接続が他方を継続的に切断・停止させる。

CYW43439の2link scheduling自体が安定しない場合だけ、connectionless advertisingへ
切り替える。

## 関連資料

- [BLE_TODO.md](../../BLE_TODO.md)
- [CADENCE_TODO.md](../../CADENCE_TODO.md)
- [BLE::UART custom cycle demo](custom_cycle_uart_demo.ja.md)
- [Dual GC9A01 cycle host](dual_gc9a01_cycle_host.ja.md)
- [Cycle host UART central](../../lib/ble_cycle_host/uart_central.rb)
- [Cycle host runtime central patch](../../lib/ble_cycle_host/uart_central_patch.rb)
- [Cycle sensor UART peripheral](../../lib/ble_cycle_sensor/uart_peripheral.rb)

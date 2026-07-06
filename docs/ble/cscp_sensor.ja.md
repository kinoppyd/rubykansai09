# Pico 2 W / PicoRubyでCSCPセンサを作るための調査記録

最終確認日: 2026-07-07 JST

## 調査対象

- Bluetooth SIG Cycling Speed and Cadence Profile / Service 1.0.1
- Raspberry Pi Pico 2 WとRP2350のリソース
- PicoRuby checkout `bc5590249611ec7c256338d08ad50d5d89c0d4a8`
- このrepositoryのMPU6050、回転検出、CSCS、BLE transport実装

実装項目と優先順位はrepository rootの`CSCP_TODO.md`にまとめています。

## CSCP/CSCSでセンサが担う役割

BLE Low Energyでは、センサはGAP PeripheralかつGATT Server、サイコンはGAP Central
かつGATT Clientです。センサは速度やケイデンスの最終値を送るのではなく、累積回転数と
最後の回転イベント時刻を送ります。サイコンが連続measurementの差分とwheel circumference
から速度、距離、ケイデンスを計算します。

標準service/characteristicは次の通りです。

| 項目 | UUID | Properties | 条件 |
| --- | --- | --- | --- |
| Cycling Speed and Cadence Service | `0x1816` | Primary Service | 必須、1 instance |
| CSC Measurement | `0x2A5B` | Notify | 必須 |
| Measurement CCCD | `0x2902` | Read, Write | 必須 |
| CSC Feature | `0x2A5C` | Read | 必須 |
| Sensor Location | `0x2A5D` | Read | Multiple Locations対応時必須。それ以外は任意 |
| SC Control Point | `0x2A55` | Write, Indicate | Wheel dataまたはMultiple Locations対応時必須 |
| Control Point CCCD | `0x2902` | Read, Write | Control Pointと同時に必須 |

Wheel dataを提供する場合、SC Control PointのSet Cumulative Value procedureは必須です。
「SC Control Pointなしでも一部サイコンでは動く」ことと「CSCSに準拠する」ことは別です。
Crank-onlyならこのversionのSC Control Pointは除外されるため、最初の準拠実装を小さくできます。

CSCS 1.0.1では、bondingをサポートし、かつCSC Featureがdevice lifetime中に変わり得る
場合だけ、CSC FeatureのIndicate propertyとCCCDも必要です。本実装はsensor modeを
device lifetime中staticにするため、最初の版ではFeature indicationを除外できます。

CSC Measurementはlittle-endianで、Flagsの後に存在bitに対応するpairを並べます。

| Mode | Flags | Payload |
| --- | ---: | --- |
| Speed only | `0x01` | Flags + wheel `uint32` + wheel time `uint16` = 7 byte |
| Cadence only | `0x02` | Flags + crank `uint16` + crank time `uint16` = 5 byte |
| Combined | `0x03` | Flags + wheel pair + crank pair = 11 byte |

event timeは1/1024秒単位のfree-running counterで、`uint16`のため64秒でrolloverします。
wheel cumulative valueはrollover禁止です。crank cumulative valueはrolloverする前提です。
典型的なnotification周期は約1秒です。停止中も同じcounterとlast event timeを周期送信すれば、
Collectorは新しいeventがないことから0 speed/cadenceを判断できます。

ProfileはadvertisingへCSCS UUIDとLocal Nameを入れることを推奨し、Appearanceも推奨します。
Assigned NumbersのAppearanceはSpeed Sensor `0x0482`、Cadence Sensor `0x0483`、Speed and
Cadence Sensor `0x0485`です。接続を速くする推奨advertising intervalは最初の30秒が
30〜60 ms、その後は1〜1.2 sです。

SecurityはLE Security Mode 1のLevel 1、2、3のいずれも許され、bondingは推奨です。
したがって、最初の相互接続を暗号化なしLevel 1で成立させ、その後bondingを検証できます。

## Pico 2 Wの制約

Pico 2 WはRP2350、520 KB SRAM、4 MB flash、最大150 MHzのdual Cortex-M33または
dual Hazard3、Bluetooth 5.2対応CYW43439を搭載します。BLE Central/Peripheralの両roleを
hardwareとしてサポートします。CYW43439はRP2350と最大33 MHzのSPIで接続され、無線用SPIの
CLKやIRQにはboard上の共有条件があります。アンテナ周辺に金属を置かないことも必要です。

520 KBはアプリが自由に使えるRuby heapの大きさではありません。調査時のfull R2P2 buildでは、
`main.c`がPico 2 W用Ruby heapを364 KiBに固定しています。2026-07-04のELFは
`text=2,344,988 byte`、`bss=443,328 byte`でした。このbuildにはBLE以外にnetworking、shell、
GC9A01等も入っているため、CSCP専用buildの最終値ではなく比較用baselineです。

PicoRubyのBTstack設定には次の静的上限があります。

- `MAX_ATT_DB_SIZE=512`
- `MAX_NR_HCI_CONNECTIONS=1`
- `MAX_NR_GATT_CLIENTS=1`
- `HCI_ACL_PAYLOAD_SIZE=259`（255 + preamble）
- controller/host ACL buffer各3

CSCS payload自体は最大11 byteなのでMTUは問題になりません。一方、GATT databaseを
Battery/Device Information/custom debug serviceまで増やす場合は512 byte上限をbuild時に
確認する必要があります。

## 現在のPicoRuby BLE実装

対象build `r2p2-picoruby-pico2_w` は`picoruby-ble`と`picoruby-ble-uart`を含み、
`picoruby-ble`は`picoruby-cyw43`と`picoruby-mbedtls`へ依存します。Ruby APIから次を使えます。

- `BLE::GattDatabase`: runtimeでATT profile dataを構築
- `BLE::AdvertisingData`: 31 byte以内のlegacy advertising dataを構築
- `BLE#advertise`, `#notify`, `#indicate`
- `#request_can_send_now_event`
- `#pop_packet`, `#pop_write_value`, `#push_read_value`
- native BTstack CSC server wrapperの`#csc_server_init`, `#csc_server_update`

Security ManagerはNo Input No Output、Secure Connections + bondingで初期化され、Peripheralの
Just Works requestはC層で自動confirmされます。bond databaseはPico SDK/BTstackのflash-backed
TLV設定を実機で確認する必要があります。

調査で確認した注意点は次の通りです。

- `BLE#start`は終了時にHCI power offする。独自poll loopは同じcleanupを自前で持つ必要がある。
- heartbeatは1秒周期、標準poll unitは100 ms。
- Peripheral advertising intervalはC層で500 ms固定。
- C層からRubyへ渡すHCI event packetは1 packet分のmailboxで、新しいeventが前のeventを
  上書きし得る。
- notification APIはcan-send-nowを待たず、送信成否をRubyへ返さない。
- Dynamic attributeのread valueとwrite queueはRuby Hash/Stringを使うため、callback量と
  heap allocationを長時間試験する必要がある。
- BTstack付属CSC serverはControl Pointとcan-send-nowを既に持つ。しかしPicoRuby wrapperの
  update引数は累積値でなく増分で、調査したupstream sourceはcrank counterをrolloverせず
  `0xffff`で飽和させる。CSCS要件に合わせた修正なしでは採用できない。

## CSCP sensor用PicoRuby patch

このリポジトリの実装はPicoRuby `bc559024` と、そのPico SDK内のBTstack
`501e6d2b8` に対する次の3 patchを必要とします。

- `patches/picoruby-cscp-sensor.patch`: native CSCS wrapper、広告interval指定、
  LE Connection Complete転送、4-slot固定長event ring、allocation-free
  `I2C#read_into`
- `patches/btstack-cscp-server.patch`: CCCD値とControl Point長の検証、切断時reset、
  indication完了/timeout、Crank Revolutionのuint16 rollover、通知要求の重複抑止
- `patches/picoruby-r2p2-irb-stability.patch`: PicoRuby upstream `cc61312c`のbackport。
  Sandboxのcompiler options二重解放を防ぎ、IRBの繰り返しcompileによるheap破壊を修正

プロジェクトrootから適用します。BTstackは入れ子のsubmoduleなので別に適用します。

```sh
git -C tmp/picoruby apply "$(pwd)/patches/picoruby-cscp-sensor.patch"
git -C tmp/picoruby apply "$(pwd)/patches/picoruby-r2p2-irb-stability.patch"
git -C tmp/picoruby/mrbgems/picoruby-r2p2/lib/pico-sdk/lib/btstack \
  apply "$(pwd)/patches/btstack-cscp-server.patch"
```

CSCP用の2 patchは`picoruby-ble`、`picoruby-i2c`、BTstackだけを変更します。
IRB安定化patchは`picoruby-sandbox`だけを変更します。
`picoruby-r2p2`の`main_task.rb`、`main.c`、USB descriptor、CMake起動経路は変更しません。
センサは標準R2P2 filesystemへRuby sourceとして転送し、`/home/app.rb`を実行します。

Pico 2 W production buildはRuby 3.4以降で実行します。

```sh
cd tmp/picoruby
ruby -S rake r2p2:picoruby:pico2_w:prod
```

2026-07-06に両patchを適用した標準`r2p2:picoruby:pico2_w:prod` full buildの
コンパイルと最終linkが成功しています。
event ringは4件のrecord metadataと共有512 byte領域を使い、最大257 byteのHCI eventへ対応
しながら、従来のeventごとのC heap確保・解放を行いません。満杯時は最古eventを破棄し、
切断など最新状態を残します。full buildの差分はbaseline比で`text +1,032 byte`、
`bss +528 byte`でした。
`I2C#read_into` は呼出側のStringへ直接読み込み、短いreadを例外にするため、10 ms samplingで
14 byte Stringを毎回作りません。

## 現行repository実装の差分

payload encoderのfield順、byte order、event time変換、停止中のperiodic notificationという
基本方針は正しいです。一方で次を直す必要があります。

1. `MPU6050BLECSC#tick`は時刻省略時に呼出しごと20 ms進めます。サンプルloopの実時間とは
   無関係なので、gyro積分とBLE event timeが誤ります。
2. 初期値は1個のMPU6050からwheel `:z`とcrank `:x`を同時検出します。別の回転体なので、
   物理的なcombined sensorとして成立しません。
3. wheel counterを`& 0xffffffff`で丸めるため、最大値の次にrolloverします。
4. CSC FeatureとSensor LocationをDynamic attributeにしていますが、read value Hashへ値を
   登録していません。実機readを確認し、static attributeにするかcallback値を登録します。
5. SC Control Pointがないため、wheel modeはCSCS準拠ではありません。
6. connected判定がATT MTU Exchange Complete依存です。LE Connection Completeを扱うべきです。
7. CCCD write確認が1秒heartbeat時だけで、notificationにsend-ready flow controlがありません。
8. 実機用entry point、Pico 2 W上のBLE test、実サイコンとの相互接続結果がありません。

## MPU6050を回転センサに使う際の限界

MPU6050は±250/500/1000/2000 dpsのgyroと±2/4/8/16 gのaccelerometerを持ち、I2Cは
最大400 kHzです。現行driverの既定は最大rangeの±2000 dps、±16 gで、sample rate divider 7、
DLPF config 3です。

クランクの通常回転はrange内に入りやすい一方、wheelは高速です。周長2.1 m、速度`v`に対する
wheel角速度は`v / r`で、2000 dps到達は概算42 km/hです。さらに半径`r`へ固定したセンサの
遠心加速度は`v^2 / r`なので、外周付近ではgyroより先にaccelerometerが飽和する場合があります。
このためwheel版は机上の合成波形だけでなく、実際の取付半径と最高速度で評価する必要があります。

## 参照資料

- Bluetooth SIG, [Cycling Speed and Cadence Profile 1.0.1](https://www.bluetooth.com/specifications/specs/cycling-speed-and-cadence-profile/)
- Bluetooth SIG, [Cycling Speed and Cadence Service 1.0.1](https://www.bluetooth.com/specifications/specs/cycling-speed-and-cadence-service/)
- Bluetooth SIG, [Assigned Numbers](https://www.bluetooth.com/specifications/assigned-numbers/)
- Raspberry Pi, [Pico-series microcontrollers](https://www.raspberrypi.com/documentation/microcontrollers/pico-series.html)
- Raspberry Pi, [Raspberry Pi Pico 2 W Datasheet](https://datasheets.raspberrypi.com/picow/pico-2-w-datasheet.pdf)
- TDK InvenSense, [MPU-6000/MPU-6050 Product Specification](https://invensense.tdk.com/wp-content/uploads/2015/02/MPU-6000-Datasheet.pdf)
- PicoRuby, [picoruby/picoruby](https://github.com/picoruby/picoruby)

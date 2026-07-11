# PicoRuby Dedicated Cadence Sensor TODO

最終更新: 2026-07-11 JST

## 目的

3台の Raspberry Pi Pico 2 W を使い、既存のスピードセンサに加えて専用の
ケイデンスセンサをホストへ同時接続する。

- スピードセンサ: Pico 2 W + MPU-6050。既存の500 ms周期通知を維持する。
- ケイデンスセンサ: Pico 2 W + MPU-6050。クランク回転を500 ms周期で通知する。
- ホスト: Pico 2 W。2台のセンサへ同時接続し、速度とケイデンスを独立計算する。
- 表示: 既存の2台のGC9A01へ速度とケイデンスをそれぞれ表示する。
- BLE profile: CSCS/CSCPは使用せず、既存の独自`BLE::UART` serviceを継続する。
- 配置: R2P2の`/home`と`/lib`へ置けるRuby sourceを用意する。trackedな`.mrb`は作らない。

## 調査結論

- [x] CYW43439とBTstackは、設定とconnection parameterが許す範囲で複数BLE接続を扱える。
- [x] 現行firmwareは`MAX_NR_HCI_CONNECTIONS 1` / `MAX_NR_GATT_CLIENTS 1`のため、
  そのままではセンサ2台へ同時接続できない。
- [x] 上記2設定を`2`へ変更したBLE + GC9A01統合firmwareがリンクできることを確認した。
- [x] 2接続化による静的RAM増加は904 bytesだった。
  - BSS: `443832` bytesから`444736` bytes。
  - link map上のheap余裕: `47096` bytesから`46192` bytes。
  - GATT client slot追加: 約144 bytes。
  - HCI connection slot追加: 約760 bytes。
- [x] 20 bytesを2台から500 msごとに受けてもapplication payloadは約80 bytes/sであり、
  BLE帯域は主な制約にならない。
- [x] 現行`BLE::UART`を2個生成するだけの実装は採用しない。
  - native側のrole、event queue、packet handler、heartbeatは共有されている。
  - `BLE::UART#start`は共有event queueを消費するblocking loopである。
  - 各instanceは単一の`@conn_handle`と単一組のGATT handleしか持たない。
  - 現行notification listener patchは静的1slotで、再登録時に前のlistenerを解除する。
- [x] 1個のBLE stack ownerに固定2slotを持たせるmulti-central方式を第一候補にする。

参考資料:

- [2センサ同時接続の詳細調査](docs/ble/multi_sensor_ble_uart_feasibility.ja.md)
- [Raspberry Pi: concurrent BLE connection discussion](https://github.com/raspberrypi/pico-feedback/issues/313)
- [BTstack memory configuration](https://bluekitchen-gmbh.com/btstack/how_to.html)
- [BTstack GATT client API](https://github.com/bluekitchen/btstack/blob/master/src/ble/gatt_client.h)
- [PicoRuby btstack_config.h](https://github.com/picoruby/picoruby/blob/7869bc06d0c610a9c702c416df81c9a38267b55b/mrbgems/picoruby-ble/include/btstack_config.h)
- [PicoRuby BLE::UART](https://github.com/picoruby/picoruby/blob/7869bc06d0c610a9c702c416df81c9a38267b55b/mrbgems/picoruby-ble-uart/mrblib/ble_uart.rb)

## 採用構成

### Sensor identity

初期実装ではpayloadを変更せず、接続先addressでsensor roleを決める。

| Role | GAP name | BLE address | Payload |
| --- | --- | --- | --- |
| Speed | 既存の`PRCycle` | 既存addressをhardcode | `BLECyclePacket` v1 |
| Cadence | `PRCad` | 実機ログ確認後にhardcode | `BLECyclePacket` v1 |

- `PRCad`はlegacy advertisingの31-byte上限内にname、flags、128-bit UUIDを収めるため短くする。
- 両センサは同じservice/RX/TX UUIDを使ってよい。
- 両センサでGATT value handleが同じ値になり得るため、hostは必ずconnection handleも使って識別する。
- sensor roleをpayloadへ追加するv2化は、address固定方式の実機検証後まで行わない。
- hardcodeは接続対象の選択であり、暗号学的なpairingや認証の代替ではない。

### Cadence calculation

ケイデンスセンサはクランクに取り付け、1回転を1 pedal revolutionとして扱う。

```text
rotations = delta_angle_mrad / 1000.0 / (2 * PI)
cadence_rpm = abs(rotations) * 60000.0 / interval_ms
```

- `interval_ms <= 0`またはfirst packetでは`0.0 rpm`にする。
- 初期値は逆回転も絶対値表示にする。
- `delta_angle_mrad == 0`が続いた場合は停止として`0.0 rpm`にする。
- notification timeoutは既存速度計と同じ1500 msを初期値にする。
- 速度推定とケイデンス推定の状態、sequence gap、timeoutを共有しない。

## Host multi-central設計

### BLE stack owner

- `BLE::UART.new(role: :central, ...)`は1回だけ呼ぶ。
- 1個のrun loopがscan、connect、GATT discovery、subscribe、notificationを処理する。
- 既存の単一接続`BLECycleHost::UARTCentral`は回帰確認用として残す。
- 新規multi-centralは固定2slotとし、hot pathでHashやArrayを生成しない。

各slotが保持する最小状態:

- sensor role
- target addressと短いname
- connection handle
- connection/discovery state
- service start/end handle
- peer RX/TX/CCCD handle
- `BLECyclePacket::FrameReader`
- 再利用する`BLECyclePacket::Decoded`
- last sequence、last packet time、gap/drop counter

### Connection sequence

1. HCI working後にpassive scanを開始する。
2. speed addressを検出したらscanを止め、speed slotへ接続する。
3. service/characteristic discoveryとCCCD subscribeを完了する。
4. speed接続を維持したままscanを再開する。
5. cadence addressを検出し、cadence slotへ接続・subscribeする。
6. 2slotがreadyになったら通常受信へ移る。
7. 片方が切断された場合は、そのslotだけをresetしてmissing sensorをscanする。
8. 残っている接続、推定値、GC9A01表示は維持する。

- GATT discoveryはslotごとに逐次実行し、初期実装では2接続のdiscoveryを並行しない。
- connection complete、disconnection、notificationはconnection handleでslotへ配送する。
- GATT query中はactive discovery slotを明示し、別slotのnotificationを捨てない。
- startup orderはspeed先、cadence先、host先のすべてを扱えるようにする。

### Notification listener

- BTstackの`GATT_CLIENT_ANY_CONNECTION`とcharacteristic `NULL`を使うpersistent listenerを第一候補にする。
- CCCD writeは各connectionに対して個別に行う。
- notification eventからconnection handleとvalue handleを取得し、Ruby側のslotへ配送する。
- pinned BTstackでwildcard listenerが期待どおり動かない場合だけ、C側に固定2要素のlistener配列を持つ。
- listener登録時に既存listenerを無条件でstopする現在の実装は置き換える。
- event queue容量はまず8を維持し、drop counterの実測後にだけ増やす。

## 変更予定ファイル

追加候補:

- `lib/ble_cycle_host/multi_uart_central.rb`
- `lib/ble_cycle_host/cadence_estimator.rb`
- `r2p2_apps/ble_cycle_cadence_sensor/home/app.rb`
- `test/ble_cycle_multi_uart_central_test.rb`
- `test/ble_cycle_cadence_estimator_test.rb`
- `patches/picoruby-ble-two-connections.patch`
- `docs/ble/cadence_sensor_demo.ja.md`

変更候補:

- `r2p2_apps/ble_cycle_host/home/app.rb`
- `patches/picoruby-ble-central-notification-listener.patch`
- `docs/ble/custom_cycle_uart_demo.ja.md`
- `docs/ble/dual_gc9a01_cycle_host.ja.md`
- `BLE_TODO.md`

維持するもの:

- `lib/ble_cycle_packet.rb`の20-byte payload v1。
- `lib/ble_cycle_sensor/uart_peripheral.rb`のperipheral API。
- `lib/ble_cycle_host/uart_central.rb`の単一接続API。
- 既存speed sensorの500 ms周期と速度計算。
- CSCS/CSCPを使用しない方針。

## 実装ステップ

### 0. Baselineと作業保護

- [x] `features/cadence_sensor`が最新`main`から分岐していることを確認する。
- [x] 作業開始時に`git status --short`を記録する。
- [x] 既存の未コミット`r2p2_apps/ble_cycle_sensor/home/app.rb`を読み、上書きしない。
- [x] 未追跡`task_cscp.md`をstage/commitしない。
- [x] 現行test suiteを実行し、baselineを記録する。
  - 2026-07-11: `60 runs, 232 assertions, 0 failures, 0 errors`。
- [ ] 現行speed sensor 1台とhostの接続ログを保存する。
- [x] 実装用PicoRuby treeとpatch適用確認用clean treeを分ける。

### 1. CadenceEstimator

- [x] `BLECycleHost::CadenceEstimator`を追加する。
- [x] `delta_angle_mrad`と`interval_ms`からrpmを計算する。
- [x] first packet、interval 0、停止、逆回転、timeoutを実装する。
- [x] sequence rollover、gap、重複packetの扱いを決める。
  - 重複packetは推定値とtimeoutを更新せず、`duplicate_count`だけを増やす。
- [x] loop中に新しいHash/Arrayを生成しない。
- [x] `test/ble_cycle_cadence_estimator_test.rb`を追加する。
- [x] 1回転/1000 msが約60 rpmになることをtestする。
- [x] speed estimatorからcadence値を取得していないことをtestする。

Commit checkpoint:

```text
Add independent cadence estimator
```

### 2. Cadence sensor app

- [x] `r2p2_apps/ble_cycle_cadence_sensor/home/app.rb`を追加する。
- [x] 既存sensor appと同じMPU-6050 driver、rotation detector、I2C初期値を使う。
- [x] `DEVICE_NAME = "PRCad"`、`NOTIFY_PERIOD_MS = 500`を設定する。
- [ ] fake modeで接続経路を確認してから`USE_MPU = true`へ切り替える。
- [x] serial logへ`sensor_role` / `cadence`を出し、speed sensorと識別できるようにする。
- [x] cadence専用の`AXIS`、`DIRECTION`、deadbandをapp先頭で調整可能にする。
- [x] first packet、I2C error、saturation、dt skippedのflagを既存sensorと揃える。
- [x] R2P2で必要な`/home`と`/lib`の配置一覧を確認する。
  - `docs/ble/cadence_sensor_demo.ja.md`に配線、配置、fake/MPU確認手順を記録した。
- [x] CRubyとPicoRuby `mrbc`でappをcompileできることを確認する。
- [ ] 単一接続hostまたはBLE scannerで500 ms notificationを確認する。
- [ ] cadence sensorのBLE addressを記録する。

Commit checkpoint:

```text
Add MPU-6050 cadence sensor app
```

### 3. Host firmwareの2接続設定

- [ ] clean PicoRuby checkoutに適用できる`picoruby-ble-two-connections.patch`を追加する。
- [ ] host firmwareだけ`MAX_NR_HCI_CONNECTIONS 2`へ変更する。
- [ ] host firmwareだけ`MAX_NR_GATT_CLIENTS 2`へ変更する。
- [ ] sensor firmwareは両方とも設定値`1`を維持する。
- [ ] `MAX_NR_CONTROLLER_ACL_BUFFERS 3`とevent queue容量は初期値を維持する。
- [ ] GC9A01なしhost UF2をbuildする。
- [ ] BLE + dual GC9A01 host UF2をbuildする。
- [ ] ELFのtext/data/BSSとheap上限をbaselineと比較する。
- [ ] clean treeへ`git apply --check`が成功することを確認する。

Commit checkpoint:

```text
Allow two BLE central connections
```

### 4. Native notification配送

- [ ] notification listenerを全connection対象で1回だけ登録できるC APIを追加する。
- [ ] mrubyとmruby/c bindingの両方へ同じAPIを追加する。
- [ ] notification eventにconnection handleが保持されることをunit/synthetic packetで確認する。
- [ ] connection handleとvalue handleが同じ/異なる組み合わせを正しく識別する。
- [ ] disconnect時に不要なlistener状態を解放する。
- [ ] event queueへnotification drop counterを追加するか、既存counterで観測可能にする。
- [ ] native patch適用後のPico 2 W UF2をbuildする。
- [ ] 単一speed sensorのnotification受信を回帰確認する。

Commit checkpoint:

```text
Route BLE notifications by connection
```

### 5. MultiUARTCentral

- [ ] 1個の`BLE::UART`を所有する`BLECycleHost::MultiUARTCentral`を追加する。
- [ ] speed/cadence固定2slotを初期化する。
- [ ] address優先、name/service UUID補助のscan matchを実装する。
- [ ] speed接続完了後も接続を維持してcadence scanを再開する。
- [ ] slot単位のservice/characteristic discoveryを実装する。
- [ ] slot単位のCCCD subscribeとready stateを実装する。
- [ ] notificationをconnection handleで正しい`FrameReader`へ渡す。
- [ ] disconnection completeをconnection handleで正しいslotだけへ適用する。
- [ ] missing slotだけを再scan/reconnectする。
- [ ] 2slot ready、1slot ready、0slot readyをqueryできるAPIを用意する。
- [ ] callbackは`role, packet, reader`を返し、packetごとのHashを返さない。
- [ ] synthetic eventでscan、2回のconnect、2回のsubscribe、交互notificationをtestする。
- [ ] 両sensorのTX value handleが同じでも混線しないことをtestする。
- [ ] 一方のdisconnectが他方のstateをresetしないことをtestする。

Commit checkpoint:

```text
Add two-slot BLE UART central
```

### 6. Hostと2画面表示の統合

- [ ] host appへspeed/cadence address定数を追加する。
- [ ] 単一`UARTCentral`を`MultiUARTCentral`へ置き換える。
- [ ] speed packetだけを`SpeedEstimator`へ渡す。
- [ ] cadence packetだけを`CadenceEstimator`へ渡す。
- [ ] 速度とケイデンスのtimeoutを独立してtickする。
- [ ] speed切断中もcadence表示を更新する。
- [ ] cadence切断中もspeed表示を更新し、cadenceだけ0へ戻す。
- [ ] `CADENCE_RPM_UNAVAILABLE`固定値を有効なcadence推定値へ置き換える。
- [ ] speed GC9A01へ`speed_kmh`を渡す。
- [ ] cadence GC9A01へ`render(speed_kmh, cadence_rpm)`を渡す。
- [ ] serial logへrole、connection handle、slot state、sequence、gap、timeoutを出す。
- [ ] 通常時の高頻度debug logをcompile/app定数で抑制できるようにする。

Commit checkpoint:

```text
Display dedicated cadence sensor data
```

### 7. 段階的な実機検証

- [ ] 新host UF2 + 既存speed sensor 1台で回帰確認する。
- [ ] cadence sensor 1台だけで接続、通知、rpm計算を確認する。
- [ ] speed real + cadence fakeで2接続を確認する。
- [ ] speed fake + cadence realで2接続を確認する。
- [ ] speed real + cadence realで2接続を確認する。
- [ ] serial logに異なる2個のconnection handleが出ることを確認する。
- [ ] 両slotで`NUS central ready`相当の状態になることを確認する。
- [ ] 両sensorが450..650 ms程度の周期で継続更新されることを確認する。
- [ ] speedだけを再起動し、cadence接続と表示が継続することを確認する。
- [ ] cadenceだけを再起動し、speed接続と表示が継続することを確認する。
- [ ] hostを先に起動し、後から2sensorを任意順序で起動して接続できることを確認する。
- [ ] 2sensorを先に起動し、後からhostを起動して接続できることを確認する。
- [ ] cadence sensor静止時に表示が0 rpmへ戻ることを確認する。
- [ ] クランク1回転/秒相当で約60 rpmになることを確認する。
- [ ] 逆回転で絶対値rpmになることを確認する。

### 8. 長時間・メモリ・radio検証

- [ ] 2sensor + BLE host + dual GC9A01で最低30分連続動作させる。
- [ ] 可能なら2時間試験を行う。
- [ ] NoMemoryError、event queue drop、sequence gap、unexpected disconnectを記録する。
- [ ] `@rx_buffer`が継続的に増加しないことを確認する。
- [ ] DEBUGを抑制した状態でも再接続診断に必要なlogが残ることを確認する。
- [ ] event queue dropがある場合、scan reportを優先破棄してnotificationを保持する。
- [ ] event queue容量増加はdrop原因を確認してから行う。
- [ ] radio schedulingが不安定な場合、connection intervalを50..100 ms程度で検証する。
- [ ] 500 ms notification周期は変更せず、connection parameterだけを調整する。
- [ ] 最終ELFのBSS、heap余裕、UF2 sizeを記録する。

### 9. ドキュメントとbuild再現性

- [ ] `docs/ble/cadence_sensor_demo.ja.md`を追加する。
- [ ] speed/cadence/hostそれぞれに書き込むUF2を明記する。
- [ ] cadence MPU-6050とPico 2 Wの配線を記載する。
- [ ] cadence sensorの`/home`と`/lib`配置を記載する。
- [ ] multi-central hostの`/home`と`/lib`配置を記載する。
- [ ] 2台のGC9A01配線を既存documentへlinkする。
- [ ] hardcodeする2個のBLE address変更箇所を記載する。
- [ ] 正常接続、片側切断、再接続、timeoutの代表logを記載する。
- [ ] `.mrb`はユーザーが転送時にcompileする方針を維持する。
- [ ] clean PicoRuby treeとpatch適用build treeを分離する。
- [ ] 全patchへ`git apply --check`を実行する。
- [ ] buildに使用したPicoRuby commit、Pico SDK version、UF2 SHA-256を記録する。

## 完了条件

- [ ] CSCS/CSCPを使わず、独自`BLE::UART` profileを維持している。
- [ ] hostに異なる2本のBLE connectionが同時に確立する。
- [ ] speedとcadenceのnotificationが500 ms目標で混線せず受信される。
- [ ] speedは既存sensorだけから計算される。
- [ ] cadenceは専用cadence sensorだけから計算される。
- [ ] cadence未接続またはtimeout時はcadenceだけ0 rpmになる。
- [ ] 一方のsensor再起動中も他方の接続、推定、表示が継続する。
- [ ] 2台のGC9A01へ速度とケイデンスが独立表示される。
- [ ] 30分試験でNoMemoryErrorと継続的なbuffer増加がない。
- [ ] serial logからslot、connection handle、sequence gap、timeoutを診断できる。
- [ ] R2P2向け`.rb`と再現可能なUF2 build手順が用意されている。
- [ ] 実装stepごとにtestを通し、対象fileだけをcommit/pushしている。

## Fallback判断

### 第一fallback: native独自GATT central

次のいずれかが再現する場合、Ruby側`BLE::UART` multi-centralを止め、同じ独自UUIDと
20-byte notificationを扱う固定2slotのnative C centralへ移行する。

- [ ] 2接続設定後も2本目のconnection/GATT clientが確立しない。
- [ ] connection handle別event配送をRuby loopで安定して処理できない。
- [ ] 30分試験でevent queue overflowまたはNoMemoryErrorが再現する。
- [ ] 一方の再接続処理が他方のnotificationを継続的に阻害する。

native centralはthin Ruby APIで`role, packet`だけをpoll可能にし、CSCS/CSCPは使わない。

### 第二fallback: connectionless advertising

CYW43439の2connection scheduling自体が不安定な場合、各sensorが500 msごとにcustom
manufacturer dataをadvertiseし、hostが常時scanする方式へ切り替える。

- 20-byte payloadへroleとsequenceを含める。
- 同じsampleを複数回advertiseしてpacket lossの影響を下げる。
- hostはsequence gapとstale timeoutを必須にする。
- ACKがないため、loss率を実測して表示の許容範囲を判断する。

### Hardware fallback

ソフトウェア変更を最小化する必要がある場合、cadence専用BLE receiver Picoを追加し、
既存hostへUART/I2Cでrpmを渡す。各receiverは現行の単一`BLE::UART`接続を維持できる。

500 ms周期を満たしにくい接続先の交互切替方式は採用しない。

## 未決事項

- [ ] cadence sensor PicoのBLE address。
- [ ] クランクへの取り付け方向と使用axis。
- [ ] cadence sensorの`DIRECTION`とdeadband。
- [ ] 実測cadenceへsmoothingが必要か。
- [ ] host側のconnection intervalを明示設定する必要があるか。
- [ ] 片側切断を画面上で表現するか、serial logだけにするか。
- [ ] Payload v2へsensor roleを追加する時期。
- [ ] native wildcard notification listenerと固定2listenerのどちらがpinned BTstackで安定するか。

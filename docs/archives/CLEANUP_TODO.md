# lib cleanup TODO（完了記録）

## 目的

`lib/`、`examples/`、`r2p2_apps/`の依存関係を2026-07-17時点で調査し、
現行サイクルコンピュータから使われていないコードと、旧方式のコードを段階的に
削除するための作業計画を残す。

調査時点の基準は`refactor/cleanup`の`4c0c975`である。現行構成は次のとおり。

- Speed sensorとcadence sensorは独自20 byte packetを`BLE::UART`で250 msごとに送る。
- Hostは`MultiUARTCentral`で2 sensorへ接続する。
- Hostはdual GC9A01を直接駆動できる。
- 3 board構成用のUART display経路も引き続きサポートする。
- CSCS/CSCPは採用しない。

静的参照の確認には`require`だけでなく、動的`require`、test、docs、Git履歴も含めた。
調査開始時のtest結果は86 runs、331 assertions、0 failures、0 errorsである。

## 調査結果

### A. 削除推奨: 旧CSCS実装一式

次の5ファイル、合計558行はCSCS/CSCP準拠方式だけで使われていたため削除した。

- [x] `lib/ble_csc_service.rb`
- [x] `lib/mpu_6050_ble_csc.rb`
- [x] `lib/ble_transport.rb`
- [x] `lib/ble_transport/fake.rb`
- [x] `lib/ble_transport/picoruby_peripheral.rb`

削除理由:

- `examples/`と`r2p2_apps/`からの参照がない。
- 5ファイルは互いと`test/ble_csc_service_test.rb`からしか参照されない。
- 2026-06-14に導入された旧CSCS方式であり、現在の独自packet + `BLE::UART`方式に
  置き換えられている。
- 今後もCSCS/CSCPを選択肢にしないというプロジェクト方針と一致しない。
- `BLETransport`という一般名だが、実体はCSC UUID、CSC GATT database、CSC payload
  helperに特化しており、現行transportの共通基盤ではない。

同時に処理する対象:

- [x] `test/ble_csc_service_test.rb`を削除する。
- [x] 旧CSCS実装を前提にしたルート`TODO.md`を`docs/archives/legacy_ble_sensor_todo.md`へ移す。
- [x] `docs/archive/`は履歴資料として変更せず、現行手順からリンクされていないことを
  確認する。
- [x] `rg "BLETransport|BLECSCService|MPU6050BLECSC"`で現行コードの参照が0件になることを
  確認する。

### B. 削除推奨: 旧single sensor Central

次の2ファイル、合計366行は1台だけへ接続する旧host実装であり、削除した。

- [x] `lib/ble_cycle_host/uart_central.rb`
- [x] `lib/ble_cycle_host/uart_central_patch.rb`

削除理由:

- 現行host appは`ble_cycle_host/multi_uart_central`だけをrequireする。
- `UARTCentral`はspeed sensor 1台のbring-upで使われたが、現在の実行appから参照されない。
- 専用testもなく、現在は古い接続state machineを維持する根拠が弱い。
- Scan、connection、GATT discovery、CCCD、notification処理が`MultiUARTCentral`と重複する。
- `CADENCE_TODO.md`では回帰確認用として一時的に残す方針だったが、2 sensor実機確認後も
  この経路を使う自動・実機回帰手順は追加されていない。

同時に処理する対象:

- [x] `docs/ble/custom_cycle_uart_demo.ja.md`をarchiveへ移すか、現行multi sensor手順へ
  統合して旧ファイルの配置指示を削除する。
- [x] `docs/ble/multi_sensor_ble_uart_feasibility.ja.md`の旧実装へのリンクを、履歴説明として
  残すか削除するか決める。
- [x] `CADENCE_TODO.md`と`PATCHES_TODO.md`は完了済み計画の履歴であるため、内容を書き換える
  場合は「後続cleanupで削除済み」と追記するだけにする。
- [x] `docs/patches/picoruby-ble-notification-listeners.ja.md`からlegacy Centralの説明を整理する。
- [x] Native BLE patchは削除しない。現行`MultiUARTCentral`がwildcard notification listenerと
  2 connection対応を引き続き必要とする。
- [x] `rg "UARTCentral|uart_central_patch"`で現行コードの参照が0件になることを確認する。

### C. ローカル生成物

- [x] `lib/.DS_Store`をローカルから削除する。

このファイルはGit管理外で、ルート`.gitignore`の`.DS_Store`規則により既にignoreされている。
したがって通常は削除commitを作らず、workspace cleanupだけ行う。

### D. 要判断: ST7789 debug console

次の実装は現行cycle appから使われていないが、独立したexample、test、日英docsを持つ。

- `lib/st7789_debug_console.rb`（598行）
- `examples/st7789_debug_console_verify.rb`
- `test/st7789_debug_console_test.rb`
- `docs/st7789/debug_console.ja.md`
- `docs/st7789/debug_console.md`

これは「未使用コード」ではなく、単体で完結した別用途のutilityである。GC9A01へ移行した
ことだけを理由に削除しない。

- [ ] このrepositoryをcycle computer専用にするなら、上記5ファイルを別repositoryまたは
  archiveへ移してから削除する。
- [x] PicoRuby display utilityとして維持し、今回のcleanup対象から外す。
- [x] 旧ST7789 BLE debug画面計画を`docs/archives/legacy_ble_sensor_todo.md`へ移した。

判断結果: cycle computer専用repositoryへ用途を限定せず、単体で検証可能なPicoRuby display
utilityを維持する。したがってlibrary、example、test、日英docsはすべて残す。

### E. 要判断: 現役ファイル内の未使用API

ファイル自体は現役だが、次のAPIはruntime appから呼ばれていない。

#### Sensorの受信API

- [x] `BLECycleSensor::UARTPeripheral#available?`
- [x] `BLECycleSensor::UARTPeripheral#read_nonblock`

Speed/cadence sensorはhostへ送信するだけで、hostからcommandを受け取らない。双方向設定を
今後追加しないなら削除する。追加予定があるなら、未使用のまま残さずprotocol TODOを作る。

#### Estimatorのtimeout API

- [x] `SpeedEstimator#tick`、`#stopped?`、`last_update_ms`
- [x] `CadenceEstimator#tick`、`#stopped?`、`last_update_ms`

Host appは`speed_last_rx_ms`、`cadence_last_rx_ms`と`rx_timed_out?`でtimeoutを独自管理しており、
Estimatorの同等機能を呼ばない。次のどちらかに統一する。

1. Host appがEstimatorの`tick`を使い、app側の重複timeout stateを削除する。
2. Estimatorからtimeout APIと関連stateを削除する。

接続切断時の強制0表示とserial logがapp側にあるため、現状では2を推奨する。

#### 重複sequence tracking

- [x] `SpeedEstimator`の`last_sequence`、`last_gap`、`gap_count`と`check_sequence`を削除可能か
  確認する。
- [x] `CadenceEstimator`のsequence処理はduplicate packetを拒否するため、重複拒否だけを残す。
- [x] Gap表示は`BLECyclePacket::FrameReader`の値をhost appが参照しているため、sequence管理を
  FrameReaderへ一本化できるかtestを追加してから判断する。

実施結果: gap/rolloverの管理は既存の`FrameReader` testで検証済みであるためEstimatorから
削除した。CadenceEstimatorは同一sequenceの再処理だけを拒否し、`duplicate_count`を保持する。

#### Test向けconvenience API

- `BLECyclePacket.decode`
- `BLECycleDisplayPacket.decode`
- 両FrameReaderの`pending_bytes`

これらはruntime appから直接呼ばれないが、testの可読性とpacket単体利用に有用である。
削除によるmemory効果も小さいため、現時点では保持する。

## 誤削除してはいけない現役コード

静的検索だけでは未使用に見えやすいものを明記する。

- `lib/ble_cycle_host/multi_uart_transport.rb`: `MultiUARTCentral#build_transport`から動的requireされる。
- `lib/ble_cycle_host/advertising_report.rb`: 現行multi Centralとscan debug appの両方で使う。
- `lib/ble_cycle_host/notification_event.rb`: 現行multi Centralのnotification振り分けに使う。
- `lib/ble_cycle_display_packet.rb`: 3 board構成のhost-to-display UARTで使う。
- `lib/ble_cycle_host/display_output.rb`: `:none`、`:uart`、single/dual GC9A01を切り替える。
- `lib/mpu_6050.rb`と`lib/mpu_6050/rotation_detector.rb`: 両sensor appの`USE_MPU`時に動的requireされる。
- `lib/ble_cycle_sensor/uart_peripheral.rb`: speed/cadence sensorの共通BLE peripheralである。

## 実施順序

### 配置対象一覧

Cleanup後にR2P2へ配置するRubyファイルは次のとおり。旧CSCSと単一Centralの`.mrb`は
配置しない。

- Speed/cadence sensor共通: `ble_cycle_packet.mrb`、
  `ble_cycle_sensor/uart_peripheral.mrb`
- MPU-6050使用sensor: `mpu_6050.mrb`、`mpu_6050/rotation_detector.mrb`
- Host: `ble_cycle_packet.mrb`、`ble_cycle_host/advertising_report.mrb`、
  `notification_event.mrb`、`multi_uart_transport.mrb`、`multi_uart_central.mrb`、
  `speed_estimator.mrb`、`cadence_estimator.mrb`、`display_output.mrb`
- 3 board構成のdisplay: `ble_cycle_display_packet.mrb`
- 各Picoの`/home/app.mrb`: 対応する`r2p2_apps/*/home/app.rb`から生成する。

### Step 1: Baselineを固定

- [x] 全testを実行し、run/assertion数を記録する。
- [x] Speed sensor、cadence sensor、hostの配置対象一覧を記録する。
- [ ] 2 sensor接続、dual GC9A01、接続indicatorを実機確認する。

開始時の実行結果は86 runs、331 assertions。実機動作はcleanup開始前の既知の状態を基準とし、
変更後の再確認は実機環境で行う。

### Step 2: CSCS一式を削除

- [x] Aの5 libraryと専用testを削除する。
- [x] 旧`TODO.md`と現行docsの参照を整理する。
- [x] 全testを実行する。
- [x] このstepだけでcommitする。

### Step 3: Single Centralを削除

- [x] Bの2 libraryを削除する。
- [x] 旧single sensor文書をarchiveまたは現行手順へ統合する。
- [x] MultiUARTCentral、advertising parser、notification parserのtestを実行する。
- [ ] 2 sensor接続を実機確認する。
- [x] このstepだけでcommitする。

### Step 4: 小さい未使用APIを整理

- [x] Sensorの受信APIを削除するかprotocol計画へ紐付ける。
- [x] Estimator timeoutの責務をappまたはEstimatorの一方へ統一する。
- [x] Speed sequence trackingの重複を解消する。
- [x] API単位にtestを更新し、挙動変更ごとにcommitする。

### Step 5: ST7789のscopeを決定

- [x] Dの判断を行う。
- [ ] 削除する場合はlibrary、example、test、日英docsを同じcommitで処理する。
- [x] 維持する場合はCLEANUP_TODO上で対象外と確定する。

### Step 6: 最終検証

- [x] `rg`で削除対象のclass/file参照が残っていないことを確認する。
- [x] 全testと`git diff --check`を実行する。
- [x] Sensor、host、host-display patch chainをclean PicoRuby treeへ適用確認する。
- [ ] 必要ならUF2を再buildし、flash/RAM sizeをcleanup前と比較する。
- [x] R2P2の`/lib`配置手順から削除済み`.mrb`を除外する。
- [ ] Speed + cadence + dual displayを実機で最終確認する。

最終自動検証結果（2026-07-17）:

- 全test: 66 runs、275 assertions、0 failures、0 errors
- `mrbc -c`: `lib/`、`examples/`、`r2p2_apps/`の全Rubyファイルが成功
- Patch chain: sensor、host、host-displayの全profileが成功
- `git diff --check`: 問題なし
- UF2: Native patchに変更がなく、RubyコードはR2P2で差し替えるため再build不要と判断
- 実機確認: 未実施。2 sensor、dual GC9A01、接続indicatorを更新後コードで確認すること

## Memoryに関する注意

R2P2の`/lib`にファイルが存在するだけなら主にflashを消費し、requireされないRuby codeは
通常heapへloadされない。したがって旧ファイルをrepositoryから削除する主目的は、誤配置、
誤require、保守対象の重複、文書の混乱をなくすことである。Heap削減を主目的にする場合は、
現行appが実際にrequireするファイル内のAPI整理と、生成した`.mrb`/UF2のsize計測を別途行う。

# Raspberry Pi Pico 2 W / PicoRuby CSCP センサ実装 TODO

最終調査日: 2026-07-05 JST

## 結論

既存コードには、MPU6050 の読み取りと回転検出、CSC Measurement の
little-endian encode、PicoRuby BLE Peripheral 用 GATT database の骨格があります。
Host Ruby の既存テストも通っています。ただし、現状は実機用アプリとして起動できる
entry point がなく、実時間処理、GATT attribute の性質、SC Control Point、BLE の
送信フロー制御、実機検証が未完了です。そのままでは CSCP 準拠のセンサとは扱えません。

最初の完成目標は **cadence-only センサ**を推奨します。MPU6050 をクランクへ固定する
構成なら物理的に成立しやすく、Crank Revolution Data だけを提供する場合、CSCS 1.0.1
では SC Control Point は除外されます。Wheel Revolution Data を提供する版では、
SC Control Point の Set Cumulative Value procedure まで実装してから完成扱いにします。

## 現在利用できる実装

- `lib/mpu_6050.rb`: 14 byte burst read、gyro calibration、実時間取得用
  `sample_now`。サンプル値はオブジェクト自身に保持し、ループ中の配列生成を避ける。
- `lib/mpu_6050/rotation_detector.rb`: gyro 積分と加速度位相による回転検出。
- `lib/ble_csc_service.rb`: speed-only 7 byte、cadence-only 5 byte、combined
  11 byte の CSC Measurement と CSC Feature の生成。
- `lib/ble_transport/picoruby_peripheral.rb`: GAP、CSCS、advertising、CCCD 書き込み、
  notification、切断後の再 advertising の骨格。
- `lib/mpu_6050_ble_csc.rb`: センサイベントを CSCS counter と notification へ接続。
- `test/ble_csc_service_test.rb`: payload、通知間隔、合成回転、飽和、長い `dt` のテスト。

調査時点で `ruby -Ilib test/ble_csc_service_test.rb` は 15 tests / 36 assertions、
failure 0 です。これは encode と合成入力の確認であり、Pico 2 W 上の BLE 動作確認では
ありません。

## P0: 実装方針とハードウェアを固定する

- [ ] 最初の製品モードを `cadence-only`、`wheel-only` のどちらにするか決める。
  最初は `cadence-only` を推奨する。
- [ ] 1個の MPU6050 を wheel と crank の両方の検出器へ同時入力する現在の既定値を
  廃止する。wheel と crank は別の回転体なので、combined sensor には2個の物理センサ、
  または別方式の回転入力が必要。
- [ ] MPU6050 の固定位置、検出軸、正方向、I2C unit、SDA/SCL pin、電源、pull-up を固定する。
- [ ] MPU6050 は最大 gyro range が ±2000 dps、accelerometer range が ±16 g であることを
  設計条件にする。2.1 m 周長の wheel では 2000 dps は概算約42 km/hに相当し、
  wheel 外周寄りでは遠心加速度も早い段階で ±16 g を超える。wheel 用途は実走速度域で
  飽和しない取付半径と検出方式を確認し、成立しなければ Hall/reed sensor または
  ±4000 dps / ±32 g 以上の IMU を選ぶ。
- [ ] `WHO_AM_I` の確認、I2C read error、短いread、センサ未接続を起動時エラーとして扱う。
- [ ] 静止状態で gyro calibration を行い、校正中は advertising/measurement を開始しない。

## P0: 時刻、回転イベント、counter を正しくする

- [ ] `MPU6050BLECSC#tick` の引数省略時に20 msずつ進める擬似時刻を実機経路から除く。
  `Machine.uptime_us` または `Machine.board_millis` を1回取得し、MPU sample、回転イベント、
  notification scheduler の全てへ同じ monotonic time を渡す。
- [ ] sampling loop を目標周期（初期値5〜10 ms）へ pacing し、実測 `dt` で gyro を積分する。
  BLE poll と I2C sampling の最悪遅延・jitter も記録する。
- [ ] uptime counter の wrap をまたぐ差分計算をテストする。
- [ ] Last Wheel/Crank Event Time は「最後に実際の1回転を検出した時刻」だけで更新し、
  停止中の定期 notification では counter と event time の両方を変更しない。
- [ ] event time を `(monotonic_ms * 1024 / 1000) mod 65536` で生成し、64秒 rollover を
  テストする。
- [ ] Cumulative Wheel Revolutions は0未満にせず、`0xffffffff` で飽和させ、rollover
  させない。現在の `& 0xffffffff` による wrap を修正する。
- [ ] Cumulative Crank Revolutions は `uint16` modulo で rollover させる。
- [ ] detector の内部 count と、SC Control Point で設定可能な wheel cumulative value を
  分離する。Control Point で値を設定した後のイベントは、その設定値を基準に加算する。
- [ ] gyro/accel saturation、`dt` skip、逆回転、振動、停止、手押し、惰性走行を含む入力で
  false positive / false negative を測定する。

## P0: CSCP / CSCS 1.0.1 の GATT を完成させる

- [ ] GAP Peripheral、GATT Server として、Primary CSCS (`0x1816`) をちょうど1個公開する。
- [ ] GAP service に Device Name (`0x2A00`) と Appearance (`0x2A01`) を追加する。
  Appearance は speed `0x0482`、cadence `0x0483`、combined `0x0485` をモードに合わせる。
- [ ] CSC Measurement (`0x2A5B`) を `Notify` のみ、CCCD (`0x2902`) を `Read | Write` で
  公開する。Measurement value を直接 `Read` / `Write` 可能にしない。
- [ ] CSC Feature (`0x2A5C`) を `Read` で公開し、wheel bit 0、crank bit 1を実際の
  sensor mode と一致させる。RFU は0にする。
- [ ] 静的な CSC Feature と Sensor Location を `DYNAMIC` にしない、または read callback
  へ初期値を必ず登録する。現行transportは `DYNAMIC` を指定したまま `push_read_value`
  していないため、実機readで空値になる可能性がある。
- [ ] Sensor Location (`0x2A5D`) を公開する場合、値を取付位置と一致させる。Multiple
  Sensor Locations featureを立てない場合は、値をdevice lifetime中staticにする。
- [ ] CCCD のreadが `0x0000` / `0x0001` を返し、writeは2 byteの `0x0000`（解除）と
  `0x0001`（notify有効）だけを受理する。それ以外は安全に拒否する。切断時は
  connectionごとのsubscribe stateをclearする。
- [ ] CCCD がnotify enabledになった後だけ、接続中に約1秒周期で CSC Measurement を送る。
- [ ] 通知できなかったtime-sensitive measurementを後から古い値のqueueとして送らない。

### Wheel Revolution Data を提供する場合の追加必須項目

- [ ] SC Control Point (`0x2A55`) を `Write | Indicate`、専用CCCDを `Read | Write` で追加する。
- [ ] Set Cumulative Value (`opcode 0x01` + `uint32`) を実装し、Response Code indication
  (`0x10`, request opcode, response value) を返す。
- [ ] indication未subscribe時の `0x81`、procedure実行中の `0x80`、未知opcode、invalid
  length、indication confirmation、30秒timeoutを処理する。
- [ ] PicoRuby側でRuby実装を拡張するか、既にlinkされているBTstackの
  `cycling_speed_and_cadence_service_server` を使うか決める。後者はcan-send-nowとControl
  Pointを持つが、現行wrapperの `csc_server_update` は累積値ではなく増分を受け取り、
  upstream実装のcrank counterはrolloverせず `0xffff` で飽和するため、そのまま採用しない。

## P0: PicoRuby BLE transport を実機で成立させる

- [ ] `PicoRubyCSCRuntime` が LE Connection Complete でconnected状態になるようにする。
  現在は ATT MTU Exchange Complete を接続判定に使うため、CentralがMTU exchangeしない場合を
  扱えない。
- [ ] subscribe writeを1秒heartbeat時だけでなく各pollで処理し、subscribe直後の遅延をなくす。
- [ ] `ATT_EVENT_CAN_SEND_NOW` と `request_can_send_now_event` を使ってnotificationを送る。
  現在は送信可能状態を確認せず `att_server_notify` を直接呼び、結果も上位へ返らない。
- [ ] PicoRuby BLE C層のpacket mailboxが1 packet分しかなく、新イベントで上書きされる設計を
  stress testする。接続・CCCD・切断を失わない固定長ring buffer、またはイベント別stateへ
  変更する。
- [ ] disconnect時にconnection handle、CCCD、pending notify/indicationを破棄し、advertisingを
  再開する。
- [ ] advertising APIでintervalを設定可能にする。CSCP推奨は最初の30秒が30〜60 ms、以後が
  1〜1.2 s。現行PicoRuby実装は800 units、すなわち500 ms固定。
- [ ] `BLE#start` と独自 `poll` loopのpower on/off責務を一本化し、例外やアプリ終了時に
  HCIを確実にpower offする。
- [ ] Security Mode 1 Level 1の非暗号化接続を最初の相互接続試験に使う。次に現在の
  PicoRuby設定（No Input No Output、Just Works、bonding）で再接続とbond keyのflash保存を確認する。

## P0: 実行可能なセンサアプリを追加する

- [ ] `examples/mpu_6050_ble_csc_sensor.rb` を作り、board配線、sensor mode、axis、direction、
  sample period、notify period、sensor locationを先頭の定数で設定できるようにする。
- [ ] 起動順を I2C初期化、MPU identity確認、gyro calibration、GATT構築、HCI power on、
  advertising開始の順にする。
- [ ] main loopで monotonic time取得、MPU sample、rotation detector、CSC state更新、BLE poll、
  sleepを行い、長時間にわたり一時配列・Hash・補間文字列を生成しない。
- [ ] USB serial logは状態遷移と集計値だけに制限し、release modeで無効化できるようにする。
- [ ] READMEにPico 2 WとMPU6050の配線、R2P2への`.mrb`配置、起動方法、サイコン側のwheel
  circumference設定を記載する。

## P1: advertising、補助service、電力

- [ ] advertising dataへFlags `0x06`、Complete/Shortened Local Name、Complete List of 16-bit
  Service UUIDsの`0x1816`、Appearanceを31 byte以内で格納する。収まらない項目はscan responseへ
  分けるAPIをPicoRubyへ追加する。
- [ ] Device Information Service (`0x180A`) にManufacturer NameとModel Numberを追加する。
- [ ] Battery Service (`0x180F`) とBattery Level (`0x2A19`) を追加し、実電圧から更新する。
- [ ] activity検出でadvertisingを開始し、10〜20秒の無活動後に切断/低電力化する方針を決める。
- [ ] bonding済みCollectorを優先するwhite listと再接続は、基本接続の完成後に実装する。

## P1: Pico 2 W のメモリ予算を守る

Pico 2 WはRP2350、520 KB SRAM、4 MB on-board flash、Bluetooth 5.2対応CYW43439を持ちます。
ただし全量をRuby objectに使えるわけではありません。調査したPicoRuby `bc559024` の
Pico 2 W production buildはRuby heapを364 KiBに固定し、BTstackは最大ATT DBを512 byte、
HCI connectionを1、GATT clientを1に制限しています。

2026-07-04のfull R2P2 build（BLE、networking、shell、GC9A01等を含む）は、参考値として
ELF `text=2,344,988 byte`、`bss=443,328 byte` でした。これはCSCP専用firmwareの値では
ないため、最終buildで測り直します。

- [ ] CSCP専用build configを作り、少なくとも `picoruby-ble`、`picoruby-cyw43`、
  `picoruby-i2c`、`picoruby-machine` と必要最小限のruntimeだけを入れる。
- [ ] `picoruby-ble-uart`、Wi-Fi/LwIP、LCD、PSG、不要なshell機能を除いた場合のflash、
  static RAM、Ruby heapの差をmap fileで記録する。
- [ ] GATT profile dataが `MAX_ATT_DB_SIZE=512` に収まることをbuild/testでassertする。
- [ ] 5〜10 ms samplingと1秒notificationを1時間継続し、GC回数、最小free heap、最大loop
  latency、packet drop、I2C errorを記録する。
- [ ] measurement payload、advertising data、I2C read buffer、log bufferを再利用する。
  sampling loopに履歴配列を持ち込まない。

## テスト

### Host / PicoRuby smoke test

- [ ] speed-only、cadence-only、combinedのpayload長・field順・little-endianを維持する。
- [ ] 64秒event-time wrap、crank `0xffff -> 0x0000`、wheel `0xffffffff` saturationを追加する。
- [ ] 擬似時計ではなく不規則な実測 `dt` で回転数とevent timeが一致するテストを追加する。
- [ ] stop中のperiodic notifyでcounter/event timeが不変であることを追加する。
- [ ] CCCDのvalid/invalid write、切断reset、再subscribeをtransport testへ追加する。
- [ ] GATT databaseのpropertiesをparseし、MeasurementがNotifyのみ、FeatureがRead、Control
  Pointが必要なmodeでWrite+Indicateであることを確認する。
- [ ] CSC Featureをdevice lifetime中に変更しない構成ではFeature indicationを除外する。
  bonding済みdeviceでfirmware更新等によりFeatureを変更可能にする場合だけ、CSCS 1.0.1の
  条件に従いIndicate propertyとCCCD、再接続後のindicationを追加する。
- [ ] SC Control Pointの全response、並行procedure、indication timeoutをテストする。
- [ ] sourceを`.mrb`へcompileし、PicoRuby VMでloadできるsmoke testを実施する。

### 実機 / 相互接続

- [ ] nRF Connectまたは同等のGATT clientでname、Appearance、`0x1816`、全characteristic、
  properties、CCCD read/writeを確認する。
- [ ] 1秒notificationの生byteを保存し、実際の手回し回数とcounter/event timeを照合する。
- [ ] 実サイコンでscan、pair/connect、speed/cadence表示、停止時0表示、再接続を確認する。
- [ ] wheel版ではサイコンからSet Cumulative Valueを実行し、次のmeasurementへ反映されることを
  確認する。
- [ ] 低速、高速、逆回転、荒れた路面、惰性、電波遮断、Central電源断、Sensor再起動を試す。
- [ ] 可能ならBluetooth PTSのCSCP/CSCS test suiteを実行する。製品化時はBluetooth SIGの
  qualification、商標、無線認証要件を別途確認する。

## 完了条件

- [ ] Pico 2 W起動後、MPU6050の実回転から標準CSCS notificationを送信できる。
- [ ] 対象モードとCSC Feature/Flags/GATT構成が一致し、wheel版はSC Control Pointを備える。
- [ ] 既知の実回転数に対するcounter欠落・二重計数が受入基準内である。
- [ ] 停止、event-time rollover、counter rollover/saturation、切断再接続で異常値を出さない。
- [ ] 1時間の連続運転でheap枯渇、packet取りこぼし、sampling破綻がない。
- [ ] 少なくとも1台の実サイコンとGATT検査アプリの両方で相互接続を確認する。

## 参照資料

- Bluetooth SIG, [Cycling Speed and Cadence Profile 1.0.1](https://www.bluetooth.com/specifications/specs/cycling-speed-and-cadence-profile/)
- Bluetooth SIG, [Cycling Speed and Cadence Service 1.0.1](https://www.bluetooth.com/specifications/specs/cycling-speed-and-cadence-service/)
- Bluetooth SIG, [Assigned Numbers](https://www.bluetooth.com/specifications/assigned-numbers/)
- Raspberry Pi, [Pico-series microcontrollers](https://www.raspberrypi.com/documentation/microcontrollers/pico-series.html)
- Raspberry Pi, [Raspberry Pi Pico 2 W Datasheet](https://datasheets.raspberrypi.com/picow/pico-2-w-datasheet.pdf)
- TDK InvenSense, [MPU-6000/MPU-6050 Product Specification](https://invensense.tdk.com/wp-content/uploads/2015/02/MPU-6000-Datasheet.pdf)
- PicoRuby, [picoruby/picoruby](https://github.com/picoruby/picoruby)
- Project note, [CSCP/CSCSセンサ調査](docs/ble/cscp_sensor.ja.md)

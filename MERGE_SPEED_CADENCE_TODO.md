# Speed/Cadence sensor統合TODO

最終更新: 2026-07-17 JST

## 目的

重複しているspeed sensor appとcadence sensor appを1つへ統合する。統合後は
Raspberry Pi Pico 2 Wごとにroleだけを設定し、同じsourceからspeed sensorまたは
cadence sensorとして動作させる。

同時に次を実施する。

- Speed sensor側のdebug設定、serial log、LED制御を統合appの基準にする。
- BLE notificationを送るたびにdebug LEDを短時間点灯する。
- MPU-6050のfake modeを完全に削除し、起動時から必ず実機を初期化する。
- 独自`BLE::UART` service、20 byte packet、250 ms周期、host側の2 slot構成は維持する。

## 現状調査

対象app:

- `r2p2_apps/ble_cycle_sensor/home/app.rb`
  - GAP nameは`PRCycle`。
  - `DEBUG_LOG`、`DEBUG_BLE`、GP25の`DEBUG_LED`、`blink`を持つ。
  - `USE_MPU = false`が初期値でfake modeが既定になっている。
- `r2p2_apps/ble_cycle_cadence_sensor/home/app.rb`
  - GAP nameは`PRCad`。
  - 起動時とTX logに`cadence` roleを出力する。
  - `USE_MPU = true`が初期値だがfake生成コードも残っている。
  - LED制御を持たない。

両appのMPU-6050 sampling、rotation detection、packet encode、BLE送信、I2C error処理は
実質的に同じである。HostはGAP address/nameでspeed slotとcadence slotを識別するため、
packetへrole fieldを追加する必要はない。

## 統合後の仕様

### Role設定

統合先を`r2p2_apps/ble_cycle_sensor/home/app.rb`とし、先頭の定数でroleを選択する。

```ruby
SENSOR_ROLE = :speed # または :cadence
```

RoleとGAP nameの対応を固定する。

| `SENSOR_ROLE` | GAP name | Host slot |
| --- | --- | --- |
| `:speed` | `PRCycle` | speed |
| `:cadence` | `PRCad` | cadence |

- 未知のroleでは起動を継続せず`ArgumentError`にする。
- Hostのaddress固定設定とname fallbackは変更しない。
- 2台へ配置するときは同じsourceの`SENSOR_ROLE`だけを変更して、それぞれ
  `/home/app.mrb`へcompileする。
- RoleごとにMPUの`AXIS`や`DIRECTION`を変える必要が生じた場合も、重複appを復活させず、
  role別の小さな定数選択として同じapp内へ置く。

### MPU-6050実機専用化

- `USE_MPU`を削除する。
- `FAKE_DELTA_ANGLE_MRAD`、`FULL_ROTATION_MRAD`、`fake_total_angle_mrad`を削除する。
- fake用のsample count更新、angle生成、flags設定分岐を削除する。
- `i2c`、`mpu_6050`、`mpu_6050/rotation_detector`を無条件でrequireする。
- I2C、MPU-6050、gyro calibration、rotation detectorを無条件で初期化する。
- 起動時にMPU-6050が存在しない場合はfakeへfallbackせず、例外とserial logで失敗を明示する。
- 既存の連続I2C error上限、`FLAG_I2C_ERROR`、`FLAG_SATURATED`、
  `FLAG_DT_SKIPPED`は維持する。
- Calibration中はセンサを静止させるという実機手順を維持する。

### Debug log

Speed sensor側を基準として次を維持する。

- `DEBUG_LOG = true`
- `DEBUG_BLE = true`
- 起動、calibration、MPU ready、BLE接続状態、TX packetのserial出力
- `TX` logには統合後の切り分け用として`SENSOR_ROLE`も出力する。
- 起動logはspeed/cadenceで別文言にせず、`BLE cycle sensor`と`sensor_role`へ統一する。
- fake modeがなくなるため`mode`出力は削除するか、常に`mpu`と出すのではなく
  `mpu_ready`を実機初期化成功の根拠にする。

### Debug LED

既存speed appの`GPIO.new(25, GPIO::OUT)`を基準にする。ただしPico 2 Wの実配線で
GP25が期待するLEDを制御できることを最初に確認する。外付けLEDの場合は直列抵抗を使い、
使用pinとactive levelを定数化する。

推奨定数:

```ruby
DEBUG_LED_PIN = 25
DEBUG_LED_ACTIVE = 1
DEBUG_LED_PULSE_MS = 30
```

送信時の仕様:

- `ble.write(payload)`を呼び出したpacketごとにLEDを点灯する。
- 250 ms周期を阻害しないよう、`sleep`を使わない。
- 点灯時刻を保存し、後続のBLE loopで30 ms以上経過したら消灯する。
- `Machine`の32 bit時刻rolloverを考慮した差分計算を使う。
- 未接続・advertising中・MPU samplingだけでは点灯しない。
- 起動時の既存`blink`は残してよいが、送信パルスと同じactive level helperを使う。
- `DEBUG_LOG`をfalseにしても送信LEDは動作させる。LED自体を無効化する必要がある場合は
  `DEBUG_LED_ENABLED`を別に設ける。

即座にON/OFFするだけでは目視できないため、`ble.write`を単純に既存`blink`で囲まない。
また、点灯のためにsamplingやBTstack event処理を30 ms停止しない。

## 実施手順

### Step 1: Baselineを固定

- [x] 現在の全testを実行し、run/assertion数を記録する。
- [x] 現行speed/cadence appを`mrbc -c`で検査する。
- [x] 現行hostが`PRCycle`と`PRCad`を別slotとして認識することを確認する。
- [ ] Speed sensor側のGP25 LEDが実機で点灯するか確認する。
- [x] Speed/cadenceそれぞれの`AXIS`、`DIRECTION`、deadband設定を記録する。

Baseline（2026-07-17）:

- Test: 66 runs、275 assertions、0 failures、0 errors
- `mrbc -c`: speed/cadence両appとも成功
- Host slot: `ble_cycle_multi_uart_central_test`で`PRCycle`と`PRCad`の分離を確認
- MPU設定: 両roleとも`AXIS = :y`、`DIRECTION = 0`、`GYRO_DEADBAND_DPS = 3.0`
- GP25 LED: 更新前・更新後とも実機確認が必要

### Step 2: Role設定を統合appへ追加

- [x] `r2p2_apps/ble_cycle_sensor/home/app.rb`へ`SENSOR_ROLE`を追加する。
- [x] `:speed`を`PRCycle`、`:cadence`を`PRCad`へ対応付ける。
- [x] 未知のroleを起動時に拒否する。
- [x] 起動logとTX logへroleを出力する。
- [x] Packet UUID、packet version/size、notification周期を変更していないことを確認する。
- [x] `mrbc -c`とhost Ruby testを実行する。
- [x] このstepを独立したcommitにする。

### Step 3: Fake modeを削除

- [x] `USE_MPU`とすべての条件分岐を削除する。
- [x] fake angle生成用の定数と状態を削除する。
- [x] MPU関連libraryを無条件でrequire、初期化する。
- [x] 初回packetのangle 0、以降の実測delta angleという既存仕様を維持する。
- [x] MPU未接続時にadvertisingへ進まず、起動失敗がserialで判別できることを確認する。
- [x] 連続I2C error、flags、statusの意味が変わっていないことを確認する。
- [x] `rg "USE_MPU|FAKE_DELTA_ANGLE|fake_total_angle|mode.*fake"`で現行sensor codeの
  fake参照が0件になることを確認する。
- [x] `mrbc -c`を実行する。
- [x] このstepを独立したcommitにする。

### Step 4: BLE送信LEDを実装

- [x] Speed sensor側のdebug LED初期化とactive level制御を統合appへ残す。
- [x] LED ON、LED OFF、送信パルス開始、期限到達時OFFを小さいhelperへ整理する。
- [x] `ble.write(payload)`ごとに送信パルスを開始する。
- [x] `sleep`なしでLEDが消灯することを確認する。
- [ ] LED点灯中もMPU samplingと250 ms notificationが継続することを確認する。
- [x] BLE未接続時には送信パルスが発生しないことを確認する。
- [x] 時刻rollover付近でもLEDが消灯する差分判定にする。
- [x] `DEBUG_LOG = false`でもLEDが動作することを確認する。
- [x] このstepを独立したcommitにする。

### Step 5: 旧cadence appを削除

- [x] 統合appを`SENSOR_ROLE = :cadence`にして、旧appと同じ`PRCad` packetを送れることを
  先に確認する。
- [x] `r2p2_apps/ble_cycle_cadence_sensor/home/app.rb`を削除する。
- [x] 空になった`r2p2_apps/ble_cycle_cadence_sensor/`を削除する。
- [x] `rg "ble_cycle_cadence_sensor"`で現行配置手順の参照を洗い出す。
- [x] Speed/cadenceの配置元が統合appだけになったことを確認する。
- [x] このstepを独立したcommitにする。

### Step 6: 文書を更新

- [x] `docs/ble/cadence_sensor_demo.ja.md`の配置元を統合appへ変更する。
- [x] 同文書からfake modeの確認手順、`USE_MPU`の切替、fake期待値を削除する。
- [x] BLE単体検証はMPU-6050実機接続を前提とする手順へ変更する。
- [x] Speed/cadence用`.mrb`の作り分けは`SENSOR_ROLE`だけで行うことを記載する。
- [x] LED pin、active level、送信時の点灯条件を記載する。
- [x] MPU未接続、calibration失敗、I2C error時の期待logを記載する。
- [x] `CADENCE_TODO.md`など完了済み計画は履歴として書き換えず、必要なら後続統合への注記だけを
  追加する。
- [x] このstepを独立したcommitにする。

### Step 7: 自動検証

- [ ] 全testを実行する。
- [ ] `lib/`、`examples/`、`r2p2_apps/`の全RubyファイルをPicoRubyの`mrbc -c`で検査する。
- [ ] `scripts/verify_picoruby_patches.sh sensor`をclean PicoRuby treeで実行する。
- [ ] Host protocolとpacket形式に変更がないことをpacket/multi Central testで確認する。
- [ ] `git diff --check`を実行する。
- [ ] fake modeと旧cadence appへの現行参照が0件であることを`rg`で確認する。

### Step 8: 実機検証

- [ ] Speed用Picoへ`SENSOR_ROLE = :speed`でcompileした`app.mrb`を配置する。
- [ ] Cadence用Picoへ`SENSOR_ROLE = :cadence`でcompileした`app.mrb`を配置する。
- [ ] 両方で`calibrating`、`mpu_ready`、正しい`sensor_role`、正しいGAP nameを確認する。
- [ ] MPU-6050を静止させた状態で不自然な回転値が増えないことを確認する。
- [ ] 両センサが250 ms間隔でTXし、TXごとに各PicoのLEDが短く点灯することを確認する。
- [ ] Hostでspeed/cadence両slotがreadyになり、packet欠落が継続的に増えないことを確認する。
- [ ] タイヤ回転でspeed meterだけが追従することを確認する。
- [ ] クランク回転でcadence meterだけが追従することを確認する。
- [ ] 一方のセンサを再起動しても、他方の接続と表示が維持されることを確認する。
- [ ] MPU未接続でfake値を送らず、起動失敗として判別できることを確認する。
- [ ] Serial logを無効化した構成でもLEDとBLE周期が正常であることを確認する。

## 完了条件

- [ ] Sensor appの実装元が1ファイルだけになっている。
- [ ] `SENSOR_ROLE`以外のコード差分なしでspeed/cadenceを作り分けられる。
- [ ] Fake modeとfake生成値がsensor runtimeおよび現行手順からなくなっている。
- [ ] MPU-6050実機がない状態でcycle packetを送信しない。
- [ ] BLE notificationごとにdebug LEDが目視可能な時間だけ点灯する。
- [ ] 250 ms送信周期、packet v1、hostの2 sensor接続、dual meter表示が回帰していない。

## Memoryと実装上の注意

- Role選択のためだけにHashや設定classを追加せず、起動時の単純な分岐でGAP nameを決める。
- Role文字列をpacketごとに生成せず、定数をserial出力へ渡す。
- LED pulse用にはdeadline 1個だけを保持し、thread、Timer object、配列を追加しない。
- Packet buffer、MPU sample object、rotation detectorは既存どおり再利用する。
- Fake分岐と旧cadence appの削除により、sourceの重複と不要なruntime branchを減らす。
- PicoRuby sourceは`/home`と`/lib`へ置き、repositoryには`.mrb`をcommitしない。

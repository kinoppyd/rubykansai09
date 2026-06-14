# サイクリングセンサ出力リファレンス

最終確認日: 2026-06-14

## 目的

このドキュメントは、一般的なサイクリングセンサの動作を再現するために、自作センサがどのデータを出力すればよいかをまとめたものです。通信規格そのものは `docs/spec.md` にまとめています。

重要な点は、単純なセンサではサイコンが「速度」や「ケイデンス」の完成値を直接受け取るとは限らないことです。多くの場合、サイコンは累積イベントカウンタと timestamp を受け取り、自分で speed、distance、cadence を計算します。

## 推奨する再構築順

| 優先度 | センサ | 理由 |
| --- | --- | --- |
| 1 | BLE speed/cadence | 最も作りやすく有用。必要なのは revolution counter と event time。 |
| 2 | BLE power | 多くのサイコンが対応し、最小 payload は小さい。 |
| 3 | Battery/device information | ペアリング体験と互換性が向上する。 |
| 4 | ANT+ speed/cadence/power | 既存サイコンでは重要だが、ANT hardware/stack/profile access が必要。 |
| 5 | Smart trainer / FTMS / FE-C | 屋内負荷制御が必要な場合だけ。 |
| 6 | Accessory profiles | ライト、レーダー、変速、タイヤ空気圧、e-bike data。対象依存。 |

## Speed Sensor

### 物理入力

- Reed switch、Hall sensor、magnetometer、optical interrupter、IMU detector などによるホイール回転イベント。
- ホイール周長は通常サイコン側で設定し、センサからは送信しません。

### BLE 出力

Cycling Speed and Cadence Service (`0x1816`) と CSC Measurement (`0x2A5B`) を使います。

Speed-only notification:

| Field | 必要な値 |
| --- | --- |
| Flags | Bit 0 set、bit 1 clear (`0x01`) |
| Cumulative Wheel Revolutions | `uint32`。有効なホイール 1 回転ごとに increment |
| Last Wheel Event Time | `uint16`。1/1024 秒 tick の event timestamp |

### ANT+ 出力

Bicycle Speed profile を使います。公開されている ANT+ profile summary では、core data として latest speed event time と cumulative wheel revolutions が挙げられ、optional として stopped flag、battery、operating time、product identity があります。

### 再現時の注意

- 回転センサを debounce する。誤検出 1 回がそのまま距離の誤差になる。
- BLE CSCS の cumulative wheel revolutions は rollover しない想定。
- Event time は 64 秒で rollover する。サイコンは modulo 差分で処理する。
- 自転車が停止している場合も、回転数と last event time を変えずに周期的に notify する。サイコンは新しい event がないことから zero speed を導出する。
- 逆回転をサポートする場合でも、BLE CSCS では 0 未満に減らさない。

## Cadence Sensor

### 物理入力

- Magnet/Hall pair、reed switch、accelerometer、IMU などによるクランク回転イベント。

### BLE 出力

CSCS の CSC Measurement を使います。

Cadence-only notification:

| Field | 必要な値 |
| --- | --- |
| Flags | Bit 0 clear、bit 1 set (`0x02`) |
| Cumulative Crank Revolutions | `uint16`。有効なクランク 1 回転ごとに increment |
| Last Crank Event Time | `uint16`。1/1024 秒 tick の event timestamp |

### ANT+ 出力

Bicycle Cadence profile を使います。公開されている ANT+ profile summary では、core data として latest cadence event time と cumulative pedal revolutions が挙げられ、optional として stopped flag、battery、operating time、product identity があります。

### 再現時の注意

- 惰性走行中の振動や磁石位置で誤ってクランク回転を数えないようにする。
- `uint16` の crank revolution counter は rollover してよい。client は modulo 差分で計算する。
- ケイデンスは delta crank revolutions と delta time からサイコンが計算する。

## Combined Speed and Cadence Sensor

### BLE 出力

1 つの CSCS service を使い、Flags の両方の bit を set します。

| Field | 必要な値 |
| --- | --- |
| Flags | Bits 0 and 1 set (`0x03`) |
| Wheel data | Cumulative Wheel Revolutions + Last Wheel Event Time |
| Crank data | Cumulative Crank Revolutions + Last Crank Event Time |

Field order は Flags、wheel data pair、crank data pair です。

### ANT+ 出力

Combined Bicycle Speed and Cadence profile を使います。ANT+ では、2 つの channel に分けた speed-only/cadence-only センサ構成も許されています。Display 側は speed-only、cadence-only、2 センサ構成、combined 構成の全てをサポートすることが推奨されています。

### 再現時の注意

- Combined sensor でも wheel と crank の event timer は独立して管理する。
- 例えば下りで惰性走行中なら、wheel pair だけが更新され、crank pair は変わらなくてよい。

## Power Meter

### 物理入力

パワーメータは通常、次を組み合わせます。

- Strain gauge、pedal spindle、crank arm、spider、bottom bracket、chainring、hub などで torque または force を測る。
- Crank または hub rotation から angular velocity を得る。
- Offset/strain compensation のために温度を測る。

機械的 power は次です。

```text
power_watts = torque_newton_meters * angular_velocity_radians_per_second
```

### BLE 出力

Cycling Power Service (`0x1818`) と Cycling Power Measurement (`0x2A63`) を使います。

最小互換 payload:

| Field | 必要な値 |
| --- | --- |
| Flags | `uint16`。optional field がなければ 0 |
| Instantaneous Power | `sint16`。Watt |

推奨 optional field:

| Optional output | 役割 |
| --- | --- |
| Crank Revolution Data | ヘッドユニットが power meter から cadence を表示できる。 |
| Accumulated Energy | energy/kJ の cross-check に使える。 |
| Pedal Power Balance | 両側計測または左右推定デバイスで有用。 |
| Accumulated Torque | 詳細解析や一部サイコン画面で有用。 |
| Wheel Revolution Data | Hub-based system で speed も出したい場合に有用。 |

### ANT+ 出力

Bicycle Power profile を使います。既存サイコンは一般に instantaneous power と accumulated power/event data を期待し、optional page として cadence、pedal balance、torque variants、calibration、manufacturer/product identity、battery などを扱います。

### 再現時の注意

- Power value は現実的な範囲に抑える。`sint16` は負の値も表現できるが、通常のサイコンはほぼ非負のライドデータを想定する。
- Cadence を含める場合、sampled rpm だけから作らず、実際の crank event timestamp を使う。
- ヘッドユニットに「パワーメータ校正」が表示される想定なら、zero-offset/calibration procedure をサポートする。
- Strain gauge を使うなら温度補償が重要。
- 純粋な emulator なら、instantaneous power と crank revolution data が最小かつ有用なターゲット。

## Heart Rate Sensor

### 物理入力

- Chest strap による電気的心拍検出、または PPG による光学式 pulse estimate。

### BLE 出力

Heart Rate Service (`0x180D`) と Heart Rate Measurement (`0x2A37`) を使います。

最小 payload:

| Field | 必要な値 |
| --- | --- |
| Flags | optional field なし、`uint8` bpm の場合 `0x00` |
| Heart Rate Measurement Value | 255 bpm 以下は `uint8` の bpm |

有用な optional field:

| Optional output | 意味 |
| --- | --- |
| Sensor Contact Status | 皮膚接触検出のサポート有無と現在の検出状態。 |
| RR-Interval | 1/1024 秒単位の beat-to-beat interval。1 個以上。 |
| Energy Expended | reset からの kJ。 |
| Body Sensor Location | Chest、wrist、finger など。 |

### ANT+ 出力

Heart Rate Monitor profile を使います。公開されている ANT+ profile summary では、core data として last heart beat、previous heart beat time、beat count、computed heart rate が挙げられ、optional として identity、operating time、capabilities、battery、swim interval summary があります。

### 再現時の注意

- 約 1 秒に 1 回 notify する。
- RR interval を送る場合、ATT MTU に収まるだけ入れ、残りは次の notification に回す。
- 接触状態が悪い場合、不自然な bpm を送るのではなく contact bit を正しく設定する。

## Smart Trainer / Indoor Bike

### 物理入力と出力

Smart trainer は次を測る場合があります。

- Rear-wheel または flywheel speed。
- Crank cadence。
- Torque/power。
- Resistance level。
- Simulated grade または target wattage state。

また次を制御する場合があります。

- Brake/resistance percentage。
- Erg mode の target power。
- Grade、wind、rolling resistance、rider mass などの simulation parameters。

### BLE 出力

制御可能な trainer では Fitness Machine Service (`0x1826`) を使います。

| Characteristic | 目的 |
| --- | --- |
| Fitness Machine Feature (`0x2ACC`) | 対応 data/control を advertised feature として示す。 |
| Indoor Bike Data (`0x2AD2`) | Speed、cadence、power、resistance、distance、energy などを flags に応じて送る。 |
| Fitness Machine Control Point (`0x2AD9`) | Control command を受け取り indication で応答する。 |
| Fitness Machine Status (`0x2ADA`) | 状態変化を報告する。 |

制御できないオンバイクセンサなら、FTMS ではなく CSCS と CPS を使います。

### ANT+ 出力

制御可能な trainer では Fitness Equipment / FE-C を使います。ANT+ FE-C は real-time workout data を broadcast し、resistance control、target power、simulation parameters、user configuration、calibration information を受け取ります。

## Environment Sensor

### 物理入力

- Temperature sensor。対象プロファイルによっては pressure/humidity もあり得ます。

### 出力

| Protocol | Output |
| --- | --- |
| ANT+ Environment | Current temperature、optional 24-hour low/high、optional file transfer。 |
| BLE Environmental Sensing Service | 対象サイコンが対応していれば Temperature characteristic と optional environmental characteristics。 |

### 再現時の注意

- ANT+ environment sensor は low rate または要求時の higher rate で温度を送ることが多い。
- 多くのサイコンは内蔵温度センサを持つため、外部センサ対応は機種差があります。

## E-Bike / Light Electric Vehicle Sensor

### 物理入力

- Wheel speed。
- Battery state of charge と voltage。
- Assist mode、travel mode、gear state。
- Motor/battery temperature。
- Range estimate と error state。

### 出力

ANT+ LEV 系の data には、speed、distance、system/gear state、current travel mode、battery、remaining range、distance since last charge、fuel/energy use、temperatures、assistance percentage、wheel circumference、errors などがあります。一部の system は gear、travel mode、lights、indicators の逆方向 command を受けます。

### 再現時の注意

- 互換性はヘッドユニット依存です。
- 目的が speed/cadence/power をサイコンに表示するだけなら、LEV より CSCS/CPS の方が簡単です。

## Electronic Shifting / Gear Sensor

### 物理入力

- Front/rear derailleur position。
- Gear tooth counts または configured gear table。
- Shift mode と battery state。

### 出力

典型的なヘッドユニット表示 data は次です。

- Front gear index。
- Rear gear index。
- Gear ratio または tooth counts。
- Battery level。
- Shift mode。

### 再現時の注意

Shimano Di2、SRAM AXS などの変速システムは、ベンダと世代によって異なります。一般的な BLE service を出せばサイコンが受けるとは考えない方がよいです。

## Lights, Radar, Tire Pressure, Suspension, Dropper

これらのアクセサリは実際のサイコン ecosystem に存在しますが、最初のターゲットには向きません。

| Accessory | 再現すべき data | Notes |
| --- | --- | --- |
| Smart lights | Light mode、battery、on/off/beam commands | ANT+ Controls または vendor private BLE/ANT が多い。 |
| Rear radar | Relative target distance/speed、threat level、battery | ベンダ固有 profile に結びつくことが多い。 |
| Tire pressure | Pressure、temperature、leak status、battery | サイコン表示対応があっても private ANT/BLE のことが多い。 |
| Suspension | Lock state、damping mode、auto/manual summaries、battery | ANT+ profile summary はあるが、サイコン対応は機種差がある。 |
| Dropper seatpost | Lock/unlock status、battery、commands | ANT+ profile は存在するが、実用上の互換範囲は狭い。 |

## 最小 BLE payload 例

### CSCS Speed-Only

```text
flags:                          uint8   0x01
cumulative_wheel_revolutions:   uint32  little endian
last_wheel_event_time:          uint16  little endian, 1/1024 s ticks
```

### CSCS Cadence-Only

```text
flags:                          uint8   0x02
cumulative_crank_revolutions:   uint16  little endian
last_crank_event_time:          uint16  little endian, 1/1024 s ticks
```

### CSCS Combined

```text
flags:                          uint8   0x03
cumulative_wheel_revolutions:   uint32  little endian
last_wheel_event_time:          uint16  little endian, 1/1024 s ticks
cumulative_crank_revolutions:   uint16  little endian
last_crank_event_time:          uint16  little endian, 1/1024 s ticks
```

### CPS Minimal Power

```text
flags:                          uint16  0x0000, little endian
instantaneous_power:            sint16  watts, little endian
```

### HRS Minimal Heart Rate

```text
flags:                          uint8   0x00
heart_rate_bpm:                 uint8
```

## Sources

- Bluetooth SIG, [Cycling Speed and Cadence Service 1.0](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/CSCS_v1.0/out/en/index-en.html)
- Bluetooth SIG, [Cycling Power Service 1.1](https://www.bluetooth.com/specifications/specs/cycling-power-service-1-1/)
- Bluetooth SIG, [Heart Rate Service 1.0](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/HRS_v1.0/out/en/index-en.html)
- Bluetooth SIG, [Fitness Machine Service 1.0](https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0/)
- Garmin Canada / THIS IS ANT, [ANT Basics](https://www.thisisant.com/developer/ant/ant-basics/)
- Garmin Canada / THIS IS ANT, [ANT+ Device Profiles](https://www.thisisant.com/developer/ant-plus/device-profiles/)

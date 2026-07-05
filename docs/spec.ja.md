# サイクリングコンピュータ用センサ通信規格

最終確認日: 2026-06-14

## 対象範囲

このドキュメントは、既存のサイクリングコンピュータと外部センサの間で使われる通信規格をまとめたものです。PicoRuby と RP2040/RP2350 系ボードで自作センサを作る前提で、一般的なヘッドユニットと互換にするために何を実装すべきかに焦点を当てています。

実装上の現実的な優先順位は次の通りです。

- 新規の自作センサでは、まず Bluetooth Low Energy (BLE) GATT を実装する。
- ANT+ は既存サイコン互換では重要だが、追加ハードウェア、ライセンス/プロファイル情報、専用ネットワークキーが必要になる前提で扱う。
- プロプライエタリなプロトコルは、特定のヘッドユニットやアクセサリを対象にする場合だけ検討する。

## 主な規格

| 規格 | 利用場面 | センサの役割 | サイコンの役割 | 実装上の意味 |
| --- | --- | --- | --- | --- |
| BLE GATT | 現代的なセンサ、スマートフォン、ウォッチ、最近のサイコン | Peripheral、GATT Server | Central、GATT Client/Collector | 標準サービス UUID を advertise し、GATT characteristic を公開し、measurement を notification で送る。 |
| ANT+ | Garmin/Wahoo/Hammerhead 世代の多くの自転車アクセサリ。特に power/speed/cadence/HR/trainer | ANT channel master / broadcast device | ANT channel slave / display | プロファイル定義の 8 バイト data page を一定間隔で broadcast する。ANT 対応無線/スタックと ANT+ プロファイル詳細が必要。 |
| Proprietary BLE/ANT/private radio | レーダー、ライト、電子変速、タイヤ空気圧、一部 e-bike | さまざま | さまざま | 互換性はベンダ依存。特定の対象がある場合だけ扱う。 |
| 有線レガシーセンサ | 古いマグネット式 speed/cadence | Reed/Hall のパルス源 | ヘッドユニットがパルスを数える | 無線規格ではない。電気的には簡単だが、無線サイコンとの互換にはプロトコル変換が必要。 |

## BLE GATT の構造

BLE の自転車センサは通常 peripheral かつ GATT server として動作します。サイコンは central として advertisement をスキャンし、接続後に service を discovery し、Client Characteristic Configuration Descriptor (CCCD) に書き込んで notification を有効化し、measurement notification を受け取ります。

自転車向け BLE サービスに共通する実装ルールは次の通りです。

- Connectable peripheral として advertise し、対象の 16-bit service UUID を advertising data または scan response に含める。
- 各サービスを Primary Service として公開する。
- 自転車向けサービスの複数バイト値は little-endian にする。
- 時間依存の measurement は `Read` ではなく `Notify` で送る。
- notify/indicate 可能な characteristic には CCCD を含める。
- 必須でなくても Battery Service (`0x180F`) と Device Information Service (`0x180A`) を追加すると互換性とペアリング体験が良くなる。
- Control point はサイコンからの `Write` と、センサからの応答 `Indicate` で構成される。

## BLE Cycling Speed and Cadence Service

ホイール速度センサ、ケイデンスセンサ、または speed/cadence 一体型センサを再現する場合に使います。

| 項目 | 値 |
| --- | --- |
| Profile | Cycling Speed and Cadence Profile (CSCP) |
| Service | Cycling Speed and Cadence Service (CSCS), UUID `0x1816` |
| Measurement characteristic | CSC Measurement, UUID `0x2A5B`, `Notify`, mandatory |
| Feature characteristic | CSC Feature, UUID `0x2A5C`, `Read`, mandatory |
| Sensor location | Sensor Location, UUID `0x2A5D`, `Read`, conditional |
| Control point | SC Control Point, UUID `0x2A55`, `Write` + `Indicate`, conditional |

### CSC Measurement の payload

CSC Measurement は 1 octet の Flags から始まります。

| Flag bit | 意味 |
| --- | --- |
| Bit 0 | Wheel Revolution Data Present |
| Bit 1 | Crank Revolution Data Present |
| Bits 2-7 | RFU。0 として送信する |

Wheel data が存在する場合、次を追加します。

| Field | Type | 単位/意味 |
| --- | --- | --- |
| Cumulative Wheel Revolutions | `uint32` | 検出したホイール回転数の累積。BLE CSCS では rollover しない想定。 |
| Last Wheel Event Time | `uint16` | 最新ホイールイベント時刻。1/1024 秒単位の free-running time。64 秒で rollover。 |

Crank data が存在する場合、次を追加します。

| Field | Type | 単位/意味 |
| --- | --- | --- |
| Cumulative Crank Revolutions | `uint16` | 検出したクランク回転数の累積。rollover してよい。 |
| Last Crank Event Time | `uint16` | 最新クランクイベント時刻。1/1024 秒単位の free-running time。64 秒で rollover。 |

Field order は Flags、存在する場合は wheel pair、存在する場合は crank pair の順です。

サイコンは連続する notification の差分から速度、距離、ケイデンスを計算します。ホイール周長はサイコン側で設定または管理され、CSCS では送信しません。

典型的な notification 間隔は約 1 秒です。この間隔はセンサ側が決めます。

### CSC Feature

`CSC Feature` は `uint16` の bit field です。

| Bit | 意味 |
| --- | --- |
| 0 | Wheel Revolution Data Supported |
| 1 | Crank Revolution Data Supported |
| 2 | Multiple Sensor Locations Supported |
| 3-15 | RFU。0 として送信する |

### SC Control Point

Wheel revolution data または multiple sensor locations をサポートする場合は必須です。主な procedure は次の通りです。

- 累積ホイール回転数の設定。
- センサ位置の更新。
- サポートされるセンサ位置の要求。

Crank-only sensor ではこの version の SC Control Point は除外されます。Wheel revolution data を送るsensorで省略すると、実用上接続できるサイコンがあっても CSCS 準拠にはなりません。

## BLE Cycling Power Service

パワーメータを再現する場合に使います。

| 項目 | 値 |
| --- | --- |
| Profile | Cycling Power Profile (CPP) |
| Service | Cycling Power Service (CPS), UUID `0x1818` |
| Feature characteristic | Cycling Power Feature, UUID `0x2A65`, `Read`, mandatory |
| Measurement characteristic | Cycling Power Measurement, UUID `0x2A63`, `Notify`, mandatory |
| Sensor location | Sensor Location, UUID `0x2A5D`, `Read`, mandatory |
| Control point | Cycling Power Control Point, UUID `0x2A66`, `Write` + `Indicate`, optional |
| Vector | Cycling Power Vector, UUID `0x2A64`, `Notify`, optional |

### Cycling Power Measurement の payload

Measurement は次から始まります。

| Field | Type | 単位/意味 |
| --- | --- | --- |
| Flags | `uint16` | Optional field の存在 bit と status bit。 |
| Instantaneous Power | `sint16` | Watt。mandatory。 |

Flags で選択される optional field には次があります。

| Optional field | 目的 |
| --- | --- |
| Pedal Power Balance | 左右寄与の推定値。 |
| Accumulated Torque | トルク積算値。 |
| Wheel Revolution Data | 速度/距離用のホイール回転数とイベント時刻。 |
| Crank Revolution Data | ケイデンス用のクランク回転数とイベント時刻。 |
| Extreme Force Magnitudes | 計測ウィンドウ内の最小/最大 force。 |
| Extreme Torque Magnitudes | 計測ウィンドウ内の最小/最大 torque。 |
| Extreme Angles | force/torque の極値が発生したクランク角。 |
| Top/Bottom Dead Spot Angles | ペダリング位相のランドマーク。 |
| Accumulated Energy | 接続開始からのエネルギー kJ。0 から始まり、rollover しない想定。 |

最小構成の BLE パワーメータは Flags と Instantaneous Power だけで成立します。ただし、Crank Revolution Data または別 CSCS cadence sensor でケイデンスも出すと、実際のサイコンで扱いやすくなります。

### Cycling Power Control Point

Control point は optional ですが、品質の高いパワーメータでは期待されます。累積ホイール値の設定、センサ位置更新、機械パラメータ設定、offset compensation/zero calibration、measurement content masking、sampling rate 要求、factory calibration date 要求などを扱います。

### Cycling Power Vector

Vector data は optional で、クランク 1 回転中の高レートな force/torque 配列向けです。高度なパワーメータを作らない限り省略します。

## BLE Heart Rate Service

サイコンにペアリングできる心拍ストラップや光学式心拍センサを再現する場合に使います。

| 項目 | 値 |
| --- | --- |
| Profile | Heart Rate Profile (HRP) |
| Service | Heart Rate Service (HRS), UUID `0x180D` |
| Measurement characteristic | Heart Rate Measurement, UUID `0x2A37`, `Notify`, mandatory |
| Body sensor location | Body Sensor Location, UUID `0x2A38`, `Read`, optional |
| Control point | Heart Rate Control Point, UUID `0x2A39`, `Write`, Energy Expended をサポートする場合 conditional |

Heart Rate Measurement は 1 octet の Flags から始まり、心拍値と optional field が続きます。

| Field | Type | 単位/意味 |
| --- | --- | --- |
| Heart Rate Measurement Value | `uint8` または `uint16` | bpm。255 bpm 以下は `uint8` を使う。 |
| Sensor Contact Status | Flags bits | 皮膚接触検出のサポート有無と検出状態。 |
| Energy Expended | `uint16` | 最後の reset からの kJ。 |
| RR-Interval | 1 個以上の `uint16` | 心拍間隔。1/1024 秒単位。 |

典型的な notification rate は約 1 秒に 1 回です。

## BLE Fitness Machine Service

屋内トレーナーまたは制御可能な負荷装置を作る場合だけ使います。通常のオンバイクセンサでは CSCS/CPS/HRS が対象です。

| 項目 | 値 |
| --- | --- |
| Service | Fitness Machine Service (FTMS), UUID `0x1826` |
| Feature | Fitness Machine Feature, UUID `0x2ACC`, `Read` |
| Indoor bike data | Indoor Bike Data, UUID `0x2AD2`, `Notify` |
| Control point | Fitness Machine Control Point, UUID `0x2AD9`, `Write` + `Indicate` |
| Status | Fitness Machine Status, UUID `0x2ADA`, `Notify` |

Indoor bike data には、feature flag に応じて speed、cadence、power、resistance、distance、energy、heart rate などを含められます。Control point command は target power、resistance、simulation parameters、session control に使われます。

## ANT+ の構造

ANT+ は ANT の上にある profile layer です。一般的な自転車用途では、センサが channel master、サイコンが display/receiver です。センサは profile 定義の 8 バイト data page を繰り返し broadcast し、サイコンは device number/type/transmission type でペアリングして該当プロファイルの page を decode します。

実装上の注意点は次の通りです。

- RP2040/RP2350 ボードには ANT radio は内蔵されていません。外部 ANT module/SoC、または licensed ANT stack を持つ無線を使います。
- ANT+ は予約された ANT+ network key と 2457 MHz 周波数を使います。公開 ANT ページでは、ANT+ membership と product certification program は 2025-06-30 に終了したとされていますが、既存デバイスのエコシステムは残っています。
- 基本 ANT payload は 8 バイト固定です。identity、product、battery などの追加情報は、別の common/profile page として時間分割で送ります。
- 多くの ANT+ 自転車センサは one-to-many の broadcast です。複数のヘッドユニットが同じセンサを受信できます。
- 正確な byte layout は profile ごとに異なります。製品互換の実装では公式 profile PDF を参照してください。

## ANT+ 自転車系プロファイルとデータ

| ANT+ profile | 用途 | 主な sensor-to-computer data |
| --- | --- | --- |
| Bicycle Speed | ホイール速度センサ | Latest speed event time、cumulative wheel revolutions、optional stopped flag、battery、operating time、manufacturer/product identity。 |
| Bicycle Cadence | クランクケイデンスセンサ | Latest cadence event time、cumulative pedal revolutions、optional stopped flag、battery、operating time、manufacturer/product identity。 |
| Combined Bicycle Speed and Cadence | 1 個のセンサで wheel と crank の両方 | 1 ANT channel 上で speed/cadence event time と cumulative revolution count を送る。 |
| Bicycle Power | パワーメータ | Instantaneous power、accumulated power、pedal balance、cadence、torque variants、calibration、manufacturer/product identity、battery。 |
| Heart Rate Monitor | 心拍ストラップ/光学式心拍 | Last heart beat、previous heart beat time、beat count、computed heart rate、identity、operating time、battery、optional swim/advanced pages。 |
| Fitness Equipment / FE-C | スマートトレーナー | Distance、speed、heart rate、cadence、power、resistance、capabilities、calibration。逆方向に resistance、target power、simulation parameters を制御。 |
| Environment | 温度センサ | Current temperature、optional 24-hour high/low、optional stored file transfer。 |
| Light Electric Vehicle | e-bike/LEV display link | Speed、distance、system state、gear state、battery、range、assist/travel mode、temperatures、errors。逆方向に gear/mode/lights を制御。 |
| Suspension / Dropper / Controls | 自転車アクセサリ制御/状態 | アクセサリ固有 status と逆方向 command。サイコン対応は機種依存。 |
| Muscle Oxygen Monitor | NIRS 筋酸素センサ | Total hemoglobin concentration、current/previous saturated hemoglobin percentage、capabilities、session markers。 |

## プロプライエタリまたは準プロプライエタリなアクセサリ

実際のサイクリング環境には存在するものの、CSCS/CPS/HRS ほど単純ではないカテゴリがあります。

- 電子変速: 選択ギア、バッテリ、場合によって shift mode を送る。Shimano Di2、SRAM AXS、Campagnolo などで差がある。
- レーダー: 後方レーダーはサイコンとペアリングされるが、実装はベンダ/プロファイル依存。互換を狙う前に対象を確定する。
- スマートライト: ANT+ Controls、private ANT、private BLE、ベンダアプリなどが混在する。
- タイヤ空気圧: pressure と battery を private ANT/BLE profile で公開するものがある。
- E-bike systems: BLE、ANT+ LEV、CAN/UART bridge、ベンダプロトコルなどが混在する。

## 派生値

サイコンは送信された counter から表示値を計算します。

| Metric | Formula |
| --- | --- |
| Speed | `(delta wheel revolutions * wheel circumference meters) / delta event time seconds` |
| Distance | `delta wheel revolutions * wheel circumference meters` |
| Cadence | `(delta crank revolutions / delta event time seconds) * 60` |
| Torque からの Power | `torque_Nm * angular_velocity_rad_per_second` |
| Energy | Power の時間積分。BLE CPS では accumulated energy を kJ で送ることもできる。 |

Rollover する event time counter は `65536` tick の modulo で差分を計算します。1/1024 秒単位なら `65536 / 1024 = 64` 秒です。

## 最小実装ターゲット

オンバイクの自作センサでは、次の順で実装するのが現実的です。

1. BLE CSCS speed/cadence sensor。
2. Watt を測定または推定する場合は BLE CPS power meter。
3. 体に装着するデバイス、または別モジュールから HR を受ける場合だけ BLE HRS。
4. Battery Service と Device Information Service。
5. 対象サイコンが必要とし、ハードウェア/法務面の道筋がある場合だけ ANT+。
6. Smart trainer/resistance unit の場合だけ FTMS。

## RP2040/RP2350 での注意

通常の RP2040/RP2350 ボードには BLE も ANT radio も内蔵されていません。Pico W 系ボードには BLE 対応 radio がありますが、firmware と PicoRuby の対応状況を確認する必要があります。設計としては、センサ処理と無線 transport を分けるのが安全です。

- Sensor layer: wheel/crank events、torque samples、heart-rate samples、battery state。
- Protocol layer: BLE GATT service encoder または ANT+ data-page encoder。
- Radio layer: BLE stack、ANT module command API、vendor SDK bridge。

## Sources

- Bluetooth SIG, [Cycling Speed and Cadence Service 1.0](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/CSCS_v1.0/out/en/index-en.html)
- Bluetooth SIG, [Cycling Speed and Cadence Profile 1.0](https://www.bluetooth.com/specifications/specs/cycling-speed-and-cadence-profile-1-0/)
- Bluetooth SIG, [Cycling Power Service 1.1](https://www.bluetooth.com/specifications/specs/cycling-power-service-1-1/)
- Bluetooth SIG, [Cycling Power Profile 1.1](https://www.bluetooth.com/specifications/specs/cycling-power-profile-1-1/)
- Bluetooth SIG, [Heart Rate Service 1.0](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/HRS_v1.0/out/en/index-en.html)
- Bluetooth SIG, [Fitness Machine Service 1.0](https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0/)
- Bluetooth SIG, [Supplement to the Bluetooth Core Specification, Data Types](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/CSS_v12/out/en/supplement-to-the-bluetooth-core-specification/data-types-specification.html)
- Garmin Canada / THIS IS ANT, [ANT Basics](https://www.thisisant.com/developer/ant/ant-basics/)
- Garmin Canada / THIS IS ANT, [ANT+ Device Profiles](https://www.thisisant.com/developer/ant-plus/device-profiles/)

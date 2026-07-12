# サイクルコンピュータのアクティビティ・アップロード形式

最終確認日: 2026-07-12

## 対象と結論

この文書は、サイクルコンピュータが記録・計算した位置、時刻、速度、距離、ケイデンス、心拍、パワー、高度などを、Strava をはじめとするライド情報サイトへ渡す際のファイル形式と通信形式をまとめるものです。センサとの無線通信（BLE CSCS/CPS、ANT+ など）は [../spec.ja.md](../spec.ja.md) を参照してください。

新しいサイクルコンピュータでは、次の優先順位を推奨します。

1. 保存・外部サービス共有の正本を FIT Activity File にする。
2. 手作業で持ち出すための GPX 1.1 も出力する。
3. レガシー互換が必要な場合だけ TCX v2 を出力する。
4. サイトへ直接送る場合は、OAuth 2.0 認可後の HTTPS API を使い、ファイル本体はサイト指定の multipart/form-data で送る。

FIT を実装できない小規模な自作機では、まず時刻付きの GPX 1.1 を確実に出すのが実用的です。ただし、パワー・ケイデンス・心拍を分析サイトに残したいなら FIT または TCX が必要です。

## 用語とデータの粒度

- アクティビティ: 一回のライド。開始時刻、スポーツ種別、集計距離・時間などを持つ。
- 記録点（record / trackpoint）: ライド中の一時点の標本。時刻と、位置・高度・速度・距離・心拍・ケイデンス・パワーなど任意の値を持つ。
- ラップ: 自動または手動で区切った集計区間。
- コース／ルート: これから走る経路。完走したアクティビティとは目的が異なる。同じ拡張子でも、サービスが期待する要素は異なる。

アクティビティでは、各記録点に UTC を明示した時刻を持たせます。Strava も FIT/TCX/GPX では各 record/trackpoint の時刻を必須としているためです（位置、標高、心拍等は任意）[^strava-uploads]。GPS を使わない室内ライドも、時刻とセンサ時系列があれば FIT/TCX で記録できます。

## ファイル形式

### FIT (.fit) — Flexible and Interoperable Data Transfer

Garmin が公開するスポーツ・フィットネス機器向けのバイナリ形式です。ファイルはヘッダ、定義メッセージとデータメッセージの列、末尾 CRC からなります。各メッセージは必要なフィールドだけを持てるため、組込み機器で小さく保存できます[^fit-protocol]。

ライドでは通常 file_id、session、lap、record、必要に応じて event を書きます。record には timestamp とともに、緯度・経度、標高、速度、累積距離、心拍、ケイデンス、パワー、気温などを入れられます。独自計測値は developer data field として意味・単位・型をファイル内で定義できます。

| 観点 | 内容 |
| --- | --- |
| 典型的な用途 | サイクルコンピュータの活動ログ、パワーメータを含む分析、クラウドへの原本アップロード |
| 長所 | バイナリで小さい。時系列・ラップ・一時停止イベント・集計値・デバイス情報を豊富に表せる。Strava、komoot、TrainingPeaks、Wahoo が扱う。 |
| 短所 | 人間が直接読めず、エンコーダ／デコーダが必要。プロフィールのバージョン差、未対応メッセージ、developer field は受信側で無視され得る。CRC と時刻・単位・invalid 値を正しく扱う必要がある。 |
| 主な制限 | 柔軟でも、任意のフィールドが任意のサイトで表示される保証はない。自社デバイス名を Strava に対応付ける FIT の manufacturer は、登録済みメーカー ID と一意な product を要する[^strava-device]。 |

FIT は未知のメッセージ／フィールドを受信側が無視し、欠落した期待値を invalid/default として扱えます[^fit-protocol]。前方互換性には有利ですが、独自値が必ず可視化される意味ではありません。初期実装では developer field に依存せず、サイトが一般に読む標準の record フィールドを優先します。

### TCX (.tcx) — Training Center Database XML v2

Garmin Training Center 由来の XML 形式です。通常は TrainingCenterDatabase → Activities → Activity → Lap → Track → Trackpoint と入れ子にし、Trackpoint に時刻、位置、標高、距離、心拍、ケイデンスなどを記録します。Strava は Garmin 定義の v2 をサポートします[^strava-uploads]。

| 観点 | 内容 |
| --- | --- |
| 典型的な用途 | FIT を出せない機器の活動ログ、旧来の Garmin 系互換、XML を直接生成・確認したい場合 |
| 長所 | テキスト XML なので目視・生成・デバッグが容易。GPX より活動・ラップ・心拍・ケイデンスを自然に表せ、拡張でパワーも伝えられる。Strava、komoot、TrainingPeaks が扱う。 |
| 短所 | FIT よりファイルが大きい。拡張 XML の namespace 実装が必要で、受信側の取り込み差も大きい。 |
| 主な制限 | 基本 TCX だけではパワーを表現できず、Garmin Activity Extension の Watts などの拡張が必要。Strava は Trackpoint の拡張から watts を読む一方、TCX の気温には対応しない。また TCX Course では Track と Lap の一部集計しか利用しない[^strava-uploads]。 |

サイクリングでは Activity Sport=Biking を使い、Trackpoint ごとに Time を書きます。Strava の種目判定はこの Sport 属性に依存し、受理する値は限定されます[^strava-uploads]。独自 XML を namespace なしで混ぜず、標準要素または明示的な extension を用います。

### GPX (.gpx) — GPS Exchange Format 1.1

GPS 軌跡交換用の XML 形式です。ルート要素 rte、トラック要素 trk、トラックセグメント trkseg、点 trkpt を持ちます。GPX 1.1 は WGS84 座標系・メートル単位を規定します[^gpx-schema]。完走ログには trk / trkseg / trkpt を使い、各 trkpt に lat、lon、time、必要なら ele を持たせます。

| 観点 | 内容 |
| --- | --- |
| 典型的な用途 | GPS 軌跡の手作業インポート／エクスポート、ナビゲーション用ルート、最小限の活動共有 |
| 長所 | 広く普及したオープンな XML で、地図ソフトや多くのサイトが扱う。構造が単純で、GPS だけを搭載する自作機でも実装しやすい。Strava、komoot、TrainingPeaks が扱う。 |
| 短所 | 標準本体は位置軌跡中心で、心拍・ケイデンス・距離・気温・パワーを規定しない。XML のため FIT より大きく、サイトごとに extension の解釈が異なる。 |
| 主な制限 | センサ値には拡張が必要。Strava は Garmin Track Point Extension v1、ClueTrust 拡張、各 trkpt 内の一般的な extension タグの一部だけを読む。未定義の独自 extension は新規サポート予定がない[^strava-uploads]。komoot からの GPX エクスポートも GPS 座標だけで、計画時の waypoint・音声ナビ・地図情報は含まれない[^komoot]。 |

GPX は位置交換には適しますが、どのセンサ値をどの時刻に得たかを完全には保てません。分析用の正本を GPX のみにせず、FIT を原本、GPX を補助出力とします。

### CSV (.csv) — カンマ区切り値

CSV は一般的な表形式テキストであり、サイクリング活動の共通スキーマではありません。例えば timestamp、latitude、longitude、altitude_m、speed_mps、heart_rate_bpm、cadence_rpm、power_w、distance_m のような独自列を定義できます。

| 観点 | 内容 |
| --- | --- |
| 典型的な用途 | 開発中のログ確認、表計算・研究用の抽出、独自サーバへの取り込み |
| 長所 | 実装・目視・表計算ソフトでの分析が容易。小さなマイコンから逐次出力しやすい。 |
| 短所 | 列名、単位、時刻表現、文字コード、欠損値、ラップ／停止の表現に標準がない。 |
| 主な制限 | 同じ CSV でも互換とは限らない。TrainingPeaks も CSV は対応レイアウトであってもアップロードできない場合があると明記している[^trainingpeaks]。Strava の活動アップロード API の対応形式にも CSV はない[^strava-uploads]。 |

CSV はデバッグ／解析用の副産物に留め、一般サイトへ送る交換形式には選びません。

### JSON (.json) — サイト固有の限定形式

JSON 自体は汎用データ表現であり、ライド活動の共通ファイル形式ではありません。Strava API は JSON を受け付けますが、対象は WeightTraining、HighIntensityIntervalTraining、Workout、Crossfit のみで、セット情報と任意の時系列を送る専用 schema です[^strava-uploads]。通常の Ride／VirtualRide のファイルアップロード代替にはなりません。

| 観点 | 内容 |
| --- | --- |
| 典型的な用途 | 各サイトの REST API の要求・応答、またはサイトが明示する限定アップロード schema |
| 長所 | Web API で扱いやすく、型・構造をサービスごとに拡張しやすい。 |
| 短所 | サイト間の共通活動ファイルではない。自前 JSON を作っても一般的なライドとして受理されるとは限らない。 |
| 主な制限 | Strava の JSON は version 1.0、タイムゾーン付き start_time、elapsed_time、少なくとも一つの set を要求する筋力トレーニング限定形式である[^strava-uploads]。 |

## サイト・機器での採用状況（2026-07-12 確認）

以下は、その形式ならすべての計測項目を必ず表示するという保証ではなく、公式にインポート対象として掲げられた形式です。

| 製品・サービス | 完了アクティビティ／ルートで扱う主形式 | 注意点 |
| --- | --- | --- |
| Strava | FIT、TCX、GPX、用途限定 JSON。fit.gz、tcx.gz、gpx.gz も API で指定可能 | 各 trackpoint/record に時刻が必要。対応フィールド・GPX extension は限定的。 |
| komoot | GPX、TCX、FIT を saved route と completed activity にインポート可能 | KML と NMEA はアップロード不可。GPX のエクスポートは GPS 座標のみ。 |
| TrainingPeaks | FIT、TCX、GPX 1.1、CSV のほか複数のベンダ形式 | CSV は形式が正しく見えても取り込めないことがある。 |
| Wahoo App | 外部で記録した活動は FIT をインポート。ルートは FIT／GPX／TCX をインポート可能 | 同じ Wahoo でも活動とルートで受け入れる形式が異なる。 |

活動ログの共通部分は FIT／TCX／GPX ですが、センサ分析を保ちたい活動ログは FIT、地図上の軌跡交換は GPX と役割分担させるのが安全です。

## 通信フォーマットとアップロード経路

### ファイルをユーザーが転送してアップロードする経路

サイクルコンピュータは USB マスストレージ／MTP、Bluetooth、Wi-Fi、またはスマートフォンアプリを介して .fit、.tcx、.gpx を端末へ渡し、ユーザーまたはアプリがサイトの Web 画面へアップロードします。これは最も実装しやすく、サイト API の認証情報を機器に保持しなくてよい経路です。

- 利点: デバイスはファイル生成だけに集中でき、サービスごとの OAuth 実装やトークン保護が不要。ユーザーは原本を保管・再アップロードできる。
- 欠点: 操作が手動になり、即時同期できない。スマートフォンアプリを挟む場合は、ファイル選択・回線・バックグラウンド動作も設計対象になる。
- 実装上の注意: FIT を原本として消さずに保管し、ユーザー向けに GPX を生成する。ファイル名だけで形式を判定せず、FIT の CRC、XML の UTF-8・namespace・必須時刻を検証する。

### HTTPS REST API にファイルを送る経路

Web サービスへの直接連携は、通常 HTTPS 上の REST API で認可と送信を行います。活動のバイナリ／XML 本体は JSON 本文ではなく、ファイルとして送ることが多いです。

Strava Upload API の例では、利用者の OAuth 2.0 認可で activity:write を取得し、活動ファイルを multipart/form-data の POST として送ります[^strava-uploads]。data_type で fit、tcx、gpx、各 gzip 形式、または限定 JSON を示し、file パートに実データを置きます。処理は非同期で、送信成功直後に活動が API から見えるとは限りません。結果をポーリングし、重複・形式不正などの失敗を処理する必要があります[^strava-uploads]。

~~~http
POST /api/v3/uploads HTTP/1.1
Authorization: Bearer <OAuth access token>
Content-Type: multipart/form-data; boundary=----boundary

------boundary
Content-Disposition: form-data; name="data_type"

fit
------boundary
Content-Disposition: form-data; name="external_id"

device-serial-1234-20260712T010203Z
------boundary
Content-Disposition: form-data; name="file"; filename="2026-07-12-ride.fit"
Content-Type: application/octet-stream

<FIT binary bytes>
------boundary--
~~~

| 観点 | 内容 |
| --- | --- |
| 利点 | ユーザー操作なしで同期でき、メタデータも API の範囲で指定できる。アップロード状態と失敗理由をアプリで扱える。 |
| 欠点 | OAuth の認可画面、access/refresh token の安全な保管・失効処理、API の利用規約・レート制限・仕様変更への追従が必要。 |
| 制限 | 送信形式、サイズ、レート制限、重複判定、公開範囲、scope はサービスごとに異なる。Web UI と公開 API の受付形式が同一とは限らない。 |

機器に OAuth トークンを直接持たせるより、通常はスマートフォンアプリまたは自社クラウドに認可・アップロードを委譲します。その際も、機器からアプリ／クラウドへ渡すデータはサービス固有 JSON ではなく FIT 原本にしておくと、複数サービスへの展開と再送が容易です。

### ベンダ間のクラウド同期

Garmin Connect、Wahoo、TrainingPeaks、Strava 等のアカウント連携は、利用者が各サービスで認可し、ベンダのクラウド同士で活動を同期する仕組みであることが多いです。これは公開されている共通のサイクルコンピュータから全サイトへの通信規格ではありません。

- 利点: ユーザーは一度の連携設定で自動同期できる。
- 欠点: 連携可否、送信されるフィールド、再送・重複処理、障害時の挙動は組合せごとに異なる。非公開 API を推測して実装すると、規約違反や仕様変更による停止につながる。
- 方針: 公開されたパートナー API の提供・契約がある場合だけ利用する。それ以外は FIT ファイル出力と、対象サイトの公開 Upload API を採用する。

## 実装時の必須チェックリスト

- [ ] 記録点の時刻を単調に記録し、UTC とタイムゾーンを混同しない。時刻未設定の GPS 点を出力しない。
- [ ] 速度・距離・標高・パワー・温度の単位を、採用形式の規定に合わせる。表示用の km/h と保存用の m/s を混同しない。
- [ ] GPS がない室内ライドでも、心拍・ケイデンス・パワー・時刻を記録する。緯度経度をゼロで埋めない。
- [ ] 集計値と時系列の整合を確認する。ただしサービス側が高度上昇量や移動時間を再計算するため、完全一致しないことはある。Strava は気圧高度計の有無などにより高度を利用または再計算する[^strava-uploads]。
- [ ] FIT では activity 用の標準メッセージ、正しい profile、CRC を用いる。独自値は developer field にしても表示されない前提で扱う。
- [ ] GPX は namespace http://www.topografix.com/GPX/1/1、version 1.1、creator を正しく出し、拡張タグは対象サイトが読むものだけを追加する。
- [ ] TCX は v2 schema と extension namespace を検証し、Activity Sport=Biking と各 Trackpoint/Time を出力する。
- [ ] API では、ネットワーク失敗時に同じファイルを安全に再送できる一意な外部 ID を使い、非同期完了・重複・形式不正を別々に表示する。
- [ ] API トークンやアカウント秘密情報を FIT/GPX/TCX、デバッグ CSV、ソースコード、ログに含めない。

## 参考資料

[^fit-protocol]: [Garmin FIT SDK — FIT Protocol](https://developer.garmin.com/fit/protocol/) — FIT のメッセージ構造、ヘッダ、CRC、developer data field。
[^gpx-schema]: [Topografix — GPX 1.1 Schema Documentation](https://www.topografix.com/gpx/1/1/) — GPX 1.1 の namespace、ルート／トラック構造、WGS84 と単位。
[^strava-uploads]: [Strava Developers — Uploading to Strava](https://developers.strava.com/docs/uploads/) — 対応ファイル形式、FIT/TCX/GPX/JSON の取り込み範囲、multipart/form-data、非同期処理、API パラメータ。
[^strava-device]: [Strava Developers — Device Mapping](https://developers.strava.com/docs/uploads/#device-mapping) — FIT のメーカー／製品 ID、TCX/GPX の creator によるデバイス対応付け。
[^komoot]: [komoot Support — Export and import Routes and Activities](https://support.komoot.com/hc/en-us/articles/10115477099674-Export-and-import-Routes-and-Activities) — GPX/TCX/FIT のインポート、GPX エクスポートの内容、非対応形式。
[^trainingpeaks]: [TrainingPeaks Help Center — Compatible Device Files](https://help.trainingpeaks.com/hc/en-us/articles/204070354-Compatible-Device-Files) — FIT、TCX、GPX 1.1、CSV などの対応と CSV の注意点。

# picoruby-ble-two-connections.patch

対象パッチ: [`patches/picoruby-ble-two-connections.patch`](../../patches/picoruby-ble-two-connections.patch)

## パッチの概要

PicoRuby同梱BTstackのcompile-time poolを、BLE connection 1本から2本へ増やすパッチである。

変更対象は次の1ファイル、2定数だけである。

```text
mrbgems/picoruby-ble/include/btstack_config.h
```

```c
#define MAX_NR_GATT_CLIENTS 2
#define MAX_NR_HCI_CONNECTIONS 2
```

元の値はいずれも`1`である。

## 必要な理由

本プロジェクトのhostはspeed sensorとcadence sensorへ同時接続する。BTstackのRuby APIを
複数slot対応にしても、native側のHCI connection poolとGATT client poolが1件のままでは
2本目のconnectionを保持できない。

2接続には両方の値を増やす必要がある。

- `MAX_NR_HCI_CONNECTIONS`: ControllerとのACL connection状態、handle、security、buffer
  管理など、link自体のslot数を決める。
- `MAX_NR_GATT_CLIENTS`: GATT client procedureとconnectionごとのclient context数を決める。

HCIだけ2にしてGATTを1のままにすると、2本目のlinkが確立してもservice discoveryやCCCD
writeを独立して進められない。GATTだけ2にしてもHCI linkを2本保持できない。

## 詳細な技術的解説

### Compile-time固定pool

BTstackはこれらのmacroからstatic storageを生成する。Runtimeでconnection数を切り替える
設定ではないため、このパッチを適用したhost UF2をbuildし直す必要がある。R2P2の`/lib`へ
Ruby fileを置くだけでは増やせない。

### 実測したRAM増加

1slot追加分の内訳はlink map上で次の値になる。

```text
GATT client:     144 bytes
HCI connection:  760 bytes
Total:           904 bytes
```

コード量は変わらず、固定pool分だけBSSが増える。2接続化そのものはPico 2 Wのmemory上の
blockerではなかったが、Ruby slot、event queue、受信String、displayを含むruntime heapの
安定性は別途確認が必要である。

再編後のhost buildではHCI storage 1,520 bytes、GATT storage 288 bytesとして2slotを確認した。
Host no-displayはBSS 443,128 bytes、heap limitまで48,264 bytes、dual-displayはBSS 444,748
bytes、heap limitまで46,180 bytesの余裕がある。Sensor buildはそれぞれ760 bytes、144 bytesの
1slotを維持する。

### 2接続の手順はRuby側で管理する

このパッチはpoolを増やすだけで、次を実装しない。

- 2台のscan/identity判定
- Connectionごとのstate machine
- GATT discoveryの逐次実行
- Connection handle別notification配送
- 片側disconnect時の再接続

本プロジェクトではBLE ownerを1個だけ生成し、固定2slotの`MultiUARTCentral`がこれらを
管理する。2個の`BLE::UART` instanceを別々に起動するとglobal packet handler/event queueを
競合して消費するため、その構成は採用しない。

### GATT procedureの逐次化

Poolは2slotあるが、初期実装ではservice discovery、characteristic discovery、CCCD writeを
sensorごとに逐次実行する。接続済みslotのnotificationを維持しながら、active discovery
slotを1個に限定することでRuby側stateを小さく保つ。

## 他に必要な説明事項

### Hostだけに適用する

Speed/cadence sensorはperipheral 1接続だけを受けるため、sensor UF2では値`1`を維持する。
不要なstatic RAM消費を避けるため、このpatchはhost build treeだけへ適用する。

### 他patchとの関係

2connection poolだけではnotificationを2本配送できない。少なくとも次が必要である。

- `picoruby-ble-notification-listeners.patch`
- `picoruby-ble-central-event-delivery.patch`
- Ruby側`MultiUARTCentral`と`NotificationEvent`

現在のpatch chainではBLE系patchの最後に適用する。

### 変更していないBTstack設定

`MAX_NR_CONTROLLER_ACL_BUFFERS`など他のbuffer数は変更していない。250 msごとに20-byte
notificationを2台から受ける現在の負荷では、まず既定値でsequence gapとdisconnectを
実測する。問題の根拠なしにbufferを増やすとRAMを消費する。

### 検証方法

次を確認する。

```text
ready_role
speed
connection_handle
64
ready_role
cadence
connection_handle
65
```

- 2本のhandleが同時にreadyである。
- 両sensorからnotificationを継続受信する。
- 一方のdisconnect中も他方のRXと表示が継続する。
- 30分以上の試験でNoMemoryErrorと継続的sequence gapがない。

2026-07-13の再編後buildはPicoRuby
`b0c1c4828b82b267dab9cabf4a372c46c2a1075e`、Pico SDK 2.2.0でlinkした。

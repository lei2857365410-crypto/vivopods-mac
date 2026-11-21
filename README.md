# VivoPods — vivo TWS 耳机的 macOS 状态栏控制台

适配 iqoo wts air3 pro添加音量条

原生 macOS 菜单栏应用，直接通过蓝牙控制 vivo / iQOO TWS 耳机：电量、降噪模式、多连接设备。

菜单栏显示耳机图标 + 左右电量（`L83 R92`），点击弹出面板，一次点击即可切换降噪模式或切换设备。

<img width="602" height="952" alt="a6396e73249b14a26e539d2b902f9628" src="https://github.com/user-attachments/assets/743000e0-394a-4405-95f1-442194957829" />

<img width="294" height="501" alt="image" src="https://github.com/user-attachments/assets/1c561108-98f1-4018-897b-592ce37d7da5" />

- 只有一只耳机有读数时就只显示那一侧；两只都没有则退回显示充电盒
- 充电中的部件带 ⚡ 并转绿，电量低于 20% 转红
- **耳机未连接时菜单栏图标自动隐藏**，连上后自动出现（蓝牙关闭 / 未授权时显示 ⚠️，
  以便仍能打开面板退出或改设置）
- 支持开机自启（`SMAppService`，也可在 系统设置 ▸ 通用 ▸ 登录项与扩展 里管理）

## 为什么要有这个

vivo 官方「vivo耳机」App 可以以 iOS-on-Mac 方式装在 Apple Silicon Mac 上，但**在 Mac 上无法连接耳机**。

排查结论（实测，非推测）：它的蓝牙链路其实完全正常——BLE GATT 已连接、可读写、
双向收发数据都通。真正卡住的是这一行，每秒重复直到超时：

```
Connecting-A2DPState:未连接 bleState:5 -- 地址: AA:BB:CC:11:22:33
```

该 App 用 iOS 的 `AVAudioSession` 判断 A2DP 是否连接（`VTWS.framework` 引用了
`_AVAudioSessionPortBluetoothA2DP` / `_AVAudioSessionPortBluetoothHFP`，并按 iOS 端口 UID
格式 `AA-BB-CC-11-22-33:output_Bluetooth` 比对）。而 macOS 的 AVAudioSession 兼容层不暴露
蓝牙 A2DP/HFP 端口类型，所以该判定**实测 62/62 次全部失败**，App 永远进不到已连接状态。

关键佐证：唯一可能的用户侧变量——把耳机设为活动音频设备——已经满足（它同时是默认
输入与输出设备），App 照样看不见。所以这不是设置能绕过的问题。

该 App 是 FairPlay 加密的正版包（主程序 `cryptid 1`，签名方 `Apple iPhone OS Application
Signing`），改包即无法启动，无法本地修复。于是有了这个原生实现。

## 功能

| 功能 | 状态 |
|---|---|
| 菜单栏左右电量 + 充电状态 | ✅ 真机验证 |
| 菜单栏一键切换降噪三档（降噪 / 关闭 / 通透） | ✅ 真机验证（设置 + 回读确认） |
| 多连接设备列表（名称 / MAC / 连接状态） | ✅ 真机验证 |
| 菜单栏切换 / 断开其他设备 | ✅ 真机验证（命令号来自 APK 反编译） |
| 原始帧调试台（收发 + 手动发帧，⌘D） | ✅ |

实测机型：**vivo TWS 5**（内部型号 id `192` = `DPD2523_BASE`，固件 2.11.1）。

## 快速开始

```bash
swift run vivopods-selftest      # 协议自测（70 项断言，不需要耳机）
swift run vivoprobe --verbose    # 对真机探测协议
./scripts/build-app.sh           # 构建 .app
open build/VivoPods.app
```

首次运行会弹蓝牙授权。允许后图标出现在菜单栏右侧。

`vivoprobe` 常用参数：

```
-t, --seconds N       运行时长（默认 25 秒）
-p, --profile P       wire profile: v4(默认) | air3 | tws3e
    --set-noise M     实测降噪设置: anc | off | transparency
    --raw HEX         发送一帧原始 content（如 001B0207），可重复
-v, --verbose         打印原始收发字节
```

## 协议

vivo TWS 用的是 **GAIA 帧**，vendor `0x001B`。同一套命令空间跑在两条物理通道上，
**但帧封装不同**——这是本项目最关键的发现。

### 两种 wire format

| | 通道 | 封装 | 谁在用 |
|---|---|---|---|
| `.classic` | RFCOMM/SPP `00000837-D102-11E1-9B23-00025B00A5A5` | `FF ver flags len \| vendor(2) cmd(2) \| payload [xor]` | 官方 **Android** App |
| `.gatt` | BLE GATT 服务 `00001100-D102-11E1-9B23-00025B00A5A5` | **裸 content**：`vendor(2) cmd(2) payload` | 官方 **iOS** App |

GATT 侧没有 `FF` 帧头（GATT 自带消息边界与长度）。该结论由两条**完整**抓包短帧确定：

```
001b850900              (5 字节)  → vendor 001B, cmd 0x8509, payload 00
001b0509141a08060b0c1d (11 字节)  → cmd 0x0509, payload 14 1a 08 06 0b 0c 1d
                                     = 20,26,8,6,11,12,29 → 2026-08-06 11:12:29
```

APK 反向印证：Android 包里出现私有 SPP UUID `00000837-…`，**完全没有** `00001100-…`
这个 GATT 服务（Android 允许应用直接开 RFCOMM，iOS 不允许，所以两端各走一条）。

本项目当前实现 `.gatt`（已真机验证）；`.classic` 的编解码已完成并有测试覆盖，
传输层待补。

### 命令

响应命令 = 请求命令 `| 0x8000`。

| 命令 | 含义 | 来源 |
|---|---|---|
| `000A 0300` / `8300` | 握手（注意用 GAIA 标准 vendor `0x000A`） | 参考实现 ✅ 真机验证 |
| `001B 0207` / `8207` | 电量查询 / 上报 | 参考实现 ✅ 真机验证 |
| `001B 0230` / `8230` | 降噪查询 / 上报 | 参考实现 ✅ 真机验证 |
| `001B 0130` / `8130` | 降噪设置 / 确认 | 参考实现 ✅ 真机验证 |
| `001B 0249` / `8249` | 多连接设备列表查询 / 上报 | 本项目抓包 ✅ 真机验证 |
| `001B 014A` | 设置多连接设备列表（切换 / 断开） | APK 反编译 ✅ 真机验证 |
| `001B 014C` | 开关多连接功能 | APK 反编译 ✅ 真机验证 |
| `001B 014D` | 从耳机记录中移除设备 | APK 反编译 ✅ 真机验证 |
| `001B 0509` / `8509` | 手机时间同步（耳机主动索要，主机应答） | 本项目抓包 ✅ |
| `001B 8224` | 耳机埋点上报（payload 内嵌 JSON） | 本项目抓包 ✅ |

### Payload 布局

**电量 `8207`**：`status L R case flags`，`flags` bit0/1/2 = 左/右/仓正在充电。
百分比 >100 视为无效（耳机不在盒中时 case 常为 `0xFF`）。

```
00 55 5E FF 00  → 左 85%  右 94%  仓 无效  均未充电
```

**降噪 `8230`/`8130`**：`status mode [noiseEffect] [transparencyEffect]`，
`mode: 0=降噪 1=关闭 2=通透`。

**多连接设备 `8249`**：

```
[status:1][count:1] 然后每台设备：
[MAC:6][未知:3][状态:1][名称长度:1][UTF-8 名称]
```

实测样本（`len=87`，3 台设备，长度算术完全自洽：2 + 34 + 27 + 24 = 87）。
文中 MAC 与设备名均已脱敏，但**保持了原始 UTF-8 字节数**，因此长度校验仍可自行验证：

```
00 03
AA BB CC 44 55 66 | 38 01 0C | 02 | 17 | "张小明的MacBook Air"  (12+11=23=0x17)
DD EE FF 77 88 99 | 5A 02 0C | 00 | 10 | "小明的iQOO 13"        (9+7=16=0x10)
11 22 33 AA BB CC | 5A 41 1C | 00 | 0D | "iQOO Pad2 Pro"        (13=0x0D)
```

状态字节语义（下发 `0x014A` 观察变化实测得到）：

- `0x00` 未连接
- `0x01` 已连接，但非当前活动设备
- `0x02` 已连接，且为当前活动设备

MAC 后那 3 字节语义仍未知，原样保留。

**下发多连接设置 `014A`**：payload 是**全量列表**，每台 7 字节 `[MAC:6][state:1]`，
不是单台指令（官方 App 也是这么做的，见 `W4/a.java` 的 `new byte[size * 7]`）。
要断开某台就把它的 state 置 0 后连整张表一起发；其余设备应**原样回传各自的状态字节**，
写成统一的 `1` 会把当前活动设备降级。

真机验证记录：下发把 iQOO 13 置为 `02` 后，其状态字节由 `00 → 01`，并被移到列表首位
（与官方 `updateDualConnectionDevices` 的重排逻辑一致），本机 Mac 保持 `02` 不受影响。

### 从 APK 取命令号的方法

```bash
jadx --no-res --no-debug-info -j 8 -d /tmp/vivo-jadx vivo耳机.apk
grep -rn 'disconnectPosition' /tmp/vivo-jadx --include='*.java'   # 定位 DualConnectionManager
```

关键在 `W4/a.java`（混淆后的 `DualConnectionManager`）：

```java
x(payload, idx)   → e(330, payload)   // 0x014A 设置设备列表
y(enable, device) → e(332, payload)   // 0x014C 开关多连接
removeDevice(...) → e(333, payload)   // 0x014D 移除设备
```

调用链 `e(cmd,data)` → `v(cmd,data)` → `b.J(cmd,data)` → `i(27, cmd, data)`，
其中 `27 = 0x1B` 正是 vivo vendor，命令号不做任何偏移，可直接使用。

顺带记一笔：`0x0249` 查询的「设置」对偶**不是** `0x0149`（我先试过，三种载荷形态
均无任何回包），而是 `0x014A`。查询与设置在这套协议里并不对称。

### 踩过的坑

写特征 `00001101-…` 的 `properties = 0x04`。这**不是**「写（带响应）」——CoreBluetooth
位定义里 `0x04 = writeWithoutResponse`，`0x08` 才是 `write`。用 `.withResponse` 发会一律
得到 `Writing is not permitted.`，且现象是「能收不能发」，很容易误判成权限问题。

## 架构

```
Sources/
├── VivoPodsKit/            纯逻辑，无 UI 依赖，可被 CLI 与 App 复用
│   ├── Gaia/               帧编解码（两种 wire format）、命令常量、Profile
│   ├── Parse/              电量 / 降噪 / 握手 / 多连接设备解析
│   ├── Models/             型号表、FastPair 广播解析
│   ├── Transport/          EarbudTransport 抽象 + BLETransport
│   └── Session/            会话编排、耳机主动请求应答
├── VivoProbe/              协议探测 CLI
├── VivoSelfTest/           零依赖自测（70 项断言）
└── VivoPodsApp/            MenuBarExtra 状态栏 App
```

### 关于测试

本机只装了 Command Line Tools（无完整 Xcode），工具链里**既没有 XCTest 也没有
swift-testing**（`import` 两者均报 no such module），因此 `swift test` 不可用。
测试改为零依赖的自测可执行文件 `vivopods-selftest`，断言向量分两类：

- 移植自参考实现 `TWS-Pods-PC/vivo/test_vivo.py`，保证与已验证的 Python 版逐字节一致
- 本机真机抓包，作为 `.gatt` 无帧头结论与多连接布局的回归保护

其中一条尤其关键：我们自己构造的时间应答帧，与官方 App 实际发出的字节**逐字节相同**。

### 构建方式

没有完整 Xcode，所以不走 `xcodebuild`：`swift build` 产出可执行文件，
`scripts/build-app.sh` 手工组装 `.app`（Info.plist + 可执行文件）再 ad-hoc 签名。

`Info.plist` 两个关键项：`LSUIElement=true`（纯状态栏、无 Dock 图标）、
`NSBluetoothAlwaysUsageDescription`（缺了 CoreBluetooth 会被系统直接拒绝）。
bundle id 固定为 `com.raybuild.vivopods`，保证重新构建后 TCC 蓝牙授权不丢。

## 致谢与许可

协议实现移植自 [TWS-Pods-PC](https://github.com/Zhaoyi-ya/TWS-Pods-PC)（GPL-3.0-only），
其上游为 **HyperEars**（vivo/iQOO 私有协议逆向：GAIA 帧结构、命令号、wire profile、
电量编码）。

因此本项目同样以 **GPL-3.0-only** 发布。

感谢社区：https://linux.do/

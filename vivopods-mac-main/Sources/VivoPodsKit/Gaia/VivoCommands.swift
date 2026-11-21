import Foundation

/// vivo TWS 的 GAIA 命令常量与连接入口。
///
/// 命令号来源分两类，注释中明确标注，避免把推测当既成事实：
/// - **[参考]** 来自 `TWS-Pods-PC`（其上游 HyperEars 对 Air3 Pro / TWS 3e 的 RFCOMM 抓包）
/// - **[实测]** 来自本机 vivo iOS App 运行日志中的 BLE GATT 收发帧
public enum VivoGaia {

    // MARK: - Vendor

    /// vivo 私有 vendor。抓包帧头 `00 1B` 即此值的大端表示。 [参考][实测]
    public static let vivoVendor: UInt16 = 0x001B
    /// GAIA 标准 vendor，仅握手用。 [参考]
    public static let gaiaVendor: UInt16 = 0x000A

    // MARK: - 命令号

    public enum Command {
        /// 握手（vendor = `gaiaVendor`）。 [参考]
        public static let handshake: UInt16 = 0x0300
        public static let handshakeResponse: UInt16 = 0x8300

        /// 电量查询 / 上报。 [参考]
        public static let queryBattery: UInt16 = 0x0207
        public static let reportBattery: UInt16 = 0x8207

        /// 降噪查询 / 上报 / 设置 / 确认。 [参考]
        public static let queryNoiseMode: UInt16 = 0x0230
        public static let reportNoiseMode: UInt16 = 0x8230
        public static let setNoiseMode: UInt16 = 0x0130
        public static let ackNoiseMode: UInt16 = 0x8130

        // ---- 以下为本机 GATT 抓包实测到的命令，payload 布局待 APK 反编译确认 ----

        /// 多连接设备列表查询 / 上报。 [实测]
        public static let queryMultiConnectDevices: UInt16 = 0x0249
        public static let reportMultiConnectDevices: UInt16 = 0x8249

        // ---- 以下多连接控制命令号取自官方 Android APK 反编译（jadx）----
        //
        // 出处：`W4/a.java`（DualConnectionManager，混淆后类名）
        //   x(payload, idx)          → e(330, payload)   设置设备列表
        //   y(enable, device)        → e(332, payload)   开关多连接功能
        //   removeDevice(...)        → e(333, payload)   移除设备
        // 调用链 e(cmd,data) → v(cmd,data) → b.J(cmd,data) → i(27, cmd, data)，
        // 其中 `27` = 0x1B 正是 vivo vendor，命令号不做任何偏移，可直接使用。

        /// 设置多连接设备列表（切换 / 断开都走这条）。`330 = 0x014A`
        ///
        /// payload 为**全量列表**，每台 7 字节：`[MAC:6][connectState:1]`。
        /// `connectState`: 0 = 断开、1 = 保持、2 = 连接为当前设备。
        public static let setMultiConnectDevices: UInt16 = 0x014A

        /// 开关多连接功能。`332 = 0x014C`，payload `[本机MAC:6][enable:1]`
        public static let setMultiConnectEnabled: UInt16 = 0x014C

        /// 从耳机的多连接记录中移除某台设备。`333 = 0x014D`
        ///
        /// payload `[目标MAC:6][本机MAC:6]`
        public static let removeMultiConnectDevice: UInt16 = 0x014D

        /// 手机时间同步：耳机主动发 `0x8509` 索要，主机回 `0x0509`。 [实测]
        public static let requestPhoneTime: UInt16 = 0x8509
        public static let replyPhoneTime: UInt16 = 0x0509

        /// 耳机埋点数据上报（payload 内含 JSON）。 [实测] 直接吸收即可。
        public static let reportTracking: UInt16 = 0x8224
    }

    // MARK: - 连接入口

    /// 私有 SPP（RFCOMM）通道。Android 版官方 App 走这条。 [参考][APK 确认]
    public static let sppUUID = "00000837-D102-11E1-9B23-00025B00A5A5"

    /// BLE GATT 服务与特征。iOS 版官方 App 走这条。 [实测]
    public enum GATT {
        public static let service = "00001100-D102-11E1-9B23-00025B00A5A5"
        /// properties 0x4 = write（带响应）
        public static let writeCharacteristic = "00001101-D102-11E1-9B23-00025B00A5A5"
        /// properties 0x12 = read + notify
        public static let notifyCharacteristic = "00001102-D102-11E1-9B23-00025B00A5A5"
        /// properties 0x16，官方 App 判定为「非目标通知特征值」，本项目同样忽略
        public static let otherCharacteristic = "00001103-D102-11E1-9B23-00025B00A5A5"
    }
}

/// 统一降噪状态域。 [参考]
public enum NoiseMode: UInt8, Sendable, CaseIterable, Identifiable {
    case anc = 0
    case off = 1
    case transparency = 2

    public var id: UInt8 { rawValue }

    public var displayName: String {
        switch self {
        case .anc: return "降噪"
        case .off: return "关闭"
        case .transparency: return "通透"
        }
    }

    public var symbolName: String {
        switch self {
        case .anc: return "ear.badge.waveform"
        case .off: return "ear"
        case .transparency: return "ear.and.waveform"
        }
    }
}

/// 字节级 wire profile：只描述帧层面的机型差异。 [参考]
///
/// 不同 vivo 机型的降噪查询/设置载荷略有出入，`select(forDeviceName:)` 负责挑选。
public struct VivoProfile: Sendable, Hashable {
    public let label: String
    public let note: String
    public let gaiaVersion: UInt8
    public let noiseQueryPayload: [UInt8]
    public let noiseSetSuffix: [UInt8]

    public init(
        label: String,
        note: String,
        gaiaVersion: UInt8,
        noiseQueryPayload: [UInt8],
        noiseSetSuffix: [UInt8]
    ) {
        self.label = label
        self.note = note
        self.gaiaVersion = gaiaVersion
        self.noiseQueryPayload = noiseQueryPayload
        self.noiseSetSuffix = noiseSetSuffix
    }

    /// Air3 Pro 实机抓包确认：GAIA v3，设置载荷 `mode 04 00`。
    public static let air3ProCaptured = VivoProfile(
        label: "Air3 Pro 抓包 v3",
        note: "上游实机确认：设置载荷 mode 04 00",
        gaiaVersion: 3,
        noiseQueryPayload: [],
        noiseSetSuffix: [4, 0]
    )

    /// 家族默认：GAIA v4。vivo TWS 5 不在型号表内，命中此项。
    public static let familyDefaultV4 = VivoProfile(
        label: "vivo 家族默认 v4",
        note: "型号未在表内时的兼容参数",
        gaiaVersion: 4,
        noiseQueryPayload: [0],
        noiseSetSuffix: [3, 1]
    )

    /// TWS 3e 参考：GAIA v3，设置载荷 `mode 03`。
    public static let tws3eV3 = VivoProfile(
        label: "TWS 3e 参考 v3",
        note: "ScrewVivoTWS：设置载荷 mode 03",
        gaiaVersion: 3,
        noiseQueryPayload: [],
        noiseSetSuffix: [3]
    )
}

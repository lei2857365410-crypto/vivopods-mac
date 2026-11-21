import Foundation

/// vivo TWS 的同一套 GAIA 命令空间（vendor `0x001B`）在两条物理通道上使用**不同的帧封装**。
///
/// 这是本项目的核心设计点，两者都经过实证：
///
/// - `.classic` —— Bluetooth Classic RFCOMM/SPP（`00000837-D102-11E1-9B23-00025B00A5A5`）。
///   完整 GAIA 帧：`FF ver flags len | vendor(2) cmd(2) | payload [xor]`。
///   vivo 官方 **Android** App 走这条（APK 中出现该私有 SPP UUID，且不含任何 GATT 服务，
///   因为 Android 允许应用直接开 RFCOMM）。
///
/// - `.gatt` —— BLE GATT（服务 `00001100-D102-11E1-9B23-00025B00A5A5`，
///   写特征 `…1101`，通知特征 `…1102`）。
///   **裸 content**：`vendor(2) cmd(2) payload`，没有 `FF`/版本/标志/长度字段，
///   因为 GATT 本身就保留了消息边界与长度。
///   vivo 官方 **iOS** App 走这条（iOS 不向非 MFi 应用开放 SPP）。
///
/// `.gatt` 无头结论来自两条**完整**抓包短帧（取自 iOS 版 App 运行日志）：
///
/// ```text
/// 001b850900              (5 字节) → vendor 001B, cmd 0x8509, payload 00
/// 001b0509141a08060b0c1d (11 字节) → vendor 001B, cmd 0x0509,
///                                     payload 14 1a 08 06 0b 0c 1d
///                                     = 20,26,8,6,11,12,29 → 2026-08-06 11:12:29
/// ```
///
/// 两帧长度与字段完全自洽，不存在被截断的可能。
public enum WireFormat: Sendable, Hashable, CaseIterable {
    /// RFCOMM/SPP：完整 GAIA 帧（带 `FF` 前导）。
    case classic
    /// BLE GATT：仅 `vendor + command + payload`。
    case gatt

    public var label: String {
        switch self {
        case .classic: return "RFCOMM/SPP (完整 GAIA 帧)"
        case .gatt: return "BLE GATT (裸 content)"
        }
    }

    /// 该封装是否携带版本/标志字段。`.gatt` 不携带，因此这些字段在解码结果中恒为 0。
    public var carriesFrameHeader: Bool {
        self == .classic
    }
}

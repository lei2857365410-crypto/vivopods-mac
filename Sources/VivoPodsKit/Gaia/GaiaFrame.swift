import Foundation

/// 一帧解码后的 GAIA 报文。
///
/// 对应参考实现 `vivo/vivo_protocol.py` 的 `Frame` dataclass。
/// `.gatt` 封装没有版本/标志字段，解码时这两项填 0。
public struct GaiaFrame: Sendable, Hashable {
    public let version: UInt8
    public let flags: UInt8
    public let vendor: UInt16
    public let command: UInt16
    public let payload: [UInt8]
    /// 原始字节（含封装头，便于调试台按收到的样子显示）。
    public let raw: [UInt8]

    public init(
        version: UInt8,
        flags: UInt8,
        vendor: UInt16,
        command: UInt16,
        payload: [UInt8],
        raw: [UInt8]
    ) {
        self.version = version
        self.flags = flags
        self.vendor = vendor
        self.command = command
        self.payload = payload
        self.raw = raw
    }

    /// GAIA 约定：响应命令 = 请求命令 `| 0x8000`。
    ///
    /// 抓包一致性验证：`0x0207`→`0x8207`（电量）、`0x0249`→`0x8249`（多连接设备列表）、
    /// `0x0509`→`0x8509`（时间同步）。
    public var isResponse: Bool {
        command & 0x8000 != 0
    }

    /// 去掉响应位后的命令号，便于与请求常量比对。
    public var baseCommand: UInt16 {
        command & 0x7FFF
    }

    /// vivo 的响应 payload 首字节普遍是状态码，`0` 表示成功。
    ///
    /// 参考实现的各 `parse_*` 均以 `payload[0] != 0` 作为拒绝条件。
    public var status: UInt8? {
        payload.first
    }

    /// 状态码为成功（或无 payload 时视为无状态可判）。
    public var isSuccess: Bool {
        status == 0
    }

    public var hexPayload: String {
        payload.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public var hexRaw: String {
        raw.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// 调试台单行摘要。
    public var debugLine: String {
        let dir = isResponse ? "◀" : "▶"
        return String(
            format: "%@ vendor=%04X cmd=%04X len=%d  %@",
            dir, vendor, command, payload.count, hexPayload
        )
    }
}

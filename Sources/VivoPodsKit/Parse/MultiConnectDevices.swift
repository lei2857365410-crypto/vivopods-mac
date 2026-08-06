import Foundation

/// 多连接设备表中的一台设备。
public struct MultiConnectDevice: Sendable, Hashable, Identifiable {
    public let macAddress: String
    /// MAC 之后的 3 字节，语义未确认（疑似设备类别 / 能力位）。原样保留供继续逆向。
    public let unknownFlags: [UInt8]
    /// 连接状态字节。
    ///
    /// 实测语义（下发 `0x014A` 观察状态变化得到，已排除单样本误判）：
    /// - `0x00` 未连接
    /// - `0x01` 已连接，但不是当前活动设备
    /// - `0x02` 已连接，且为当前活动设备
    public let stateByte: UInt8
    public let name: String

    public var id: String { macAddress }

    /// MAC 的 6 字节形式，构造 `0x014A` payload 用。
    public var macBytes: [UInt8] {
        macAddress.split(separator: ":").compactMap { UInt8($0, radix: 16) }
    }

    /// 是否已连接（`0x01` 与 `0x02` 都算已连接）。
    public var isConnected: Bool { stateByte != 0 }

    /// 是否为当前活动设备（正在出声的那台）。
    public var isActive: Bool { stateByte == 0x02 }

    public var stateLabel: String {
        switch stateByte {
        case 0x00: return "未连接"
        case 0x02: return "使用中"
        default: return "已连接"
        }
    }
}

/// 多连接的连接状态取值。
///
/// 出处：官方 APK `W4/a.java` 的 `updateDualConnectionDevices`，
/// 按 `getConnectState()` 分 0 / 1 / 2 三个分支组装下发字节。
public enum MultiConnectState: UInt8, Sendable {
    /// 断开该设备
    case disconnect = 0
    /// 保持现状
    case keep = 1
    /// 连接为当前设备
    case connect = 2
}

/// 解析 `0x8249` 多连接设备列表。
///
/// 结构（由实测样本反推，长度算术完全自洽）::
///
///     [status:1][count:1] 之后每台设备：
///     [MAC:6][未知:3][状态:1][名称长度:1][UTF-8 名称:名称长度]
///
/// 实测样本（`len=87`，3 台设备）::
///
///     00 03
///     AA BB CC 44 55 66 | 38 01 0C | 02 | 17 | "张小明的MacBook Air"  (12+11=23=0x17)
///     DD EE FF 77 88 99 | 5A 02 0C | 00 | 10 | "小明的iQOO 13"        (9+7=16=0x10)
///     11 22 33 AA BB CC | 5A 41 1C | 00 | 0D | "iQOO Pad2 Pro"        (13=0x0D)
///
/// 校验：2 + 34 + 27 + 24 = 87 ✓
public enum MultiConnectDevices {

    public static func parse(_ frame: GaiaFrame) -> [MultiConnectDevice]? {
        guard frame.vendor == VivoGaia.vivoVendor,
              frame.command == VivoGaia.Command.reportMultiConnectDevices,
              frame.payload.count >= 2,
              frame.payload[0] == 0
        else { return nil }

        let count = Int(frame.payload[1])
        var devices: [MultiConnectDevice] = []
        var i = 2

        for _ in 0..<count {
            // MAC(6) + 未知(3) + 状态(1) + 长度(1) = 11 字节定长头
            guard i + 11 <= frame.payload.count else { break }

            let mac = frame.payload[i..<(i + 6)]
                .map { String(format: "%02X", $0) }
                .joined(separator: ":")
            let flags = Array(frame.payload[(i + 6)..<(i + 9)])
            let state = frame.payload[i + 9]
            let nameLen = Int(frame.payload[i + 10])
            i += 11

            guard i + nameLen <= frame.payload.count else { break }
            let nameBytes = Array(frame.payload[i..<(i + nameLen)])
            i += nameLen

            let name = String(bytes: nameBytes, encoding: .utf8)
                ?? String(bytes: nameBytes, encoding: .isoLatin1)
                ?? "(无法解码)"

            devices.append(
                MultiConnectDevice(
                    macAddress: mac,
                    unknownFlags: flags,
                    stateByte: state,
                    name: name
                )
            )
        }

        return devices
    }
}

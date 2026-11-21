import Foundation

public struct VivoFastPairIdentity: Sendable, Hashable {
    public let uuid: UInt16
    public let bleType: UInt8
    public let protocolVersion: UInt8
    /// 广播过短时可能拿不到型号 id。
    public let modelId: Int?
    /// 部分布局在广播里带 MAC。
    public let macAddress: String?

    public var uuidLabel: String {
        switch uuid {
        case VivoFastPairAdvertisement.uuidNew: return "0x0837（新标记）"
        case VivoFastPairAdvertisement.uuidLegacy: return "0x8486（旧标记）"
        default: return String(format: "0x%04X", uuid)
        }
    }

    public var modelLabel: String? {
        modelId.flatMap { VivoModelCatalog.modelIdLabel($0) }
    }
}

/// vivo FastPair BLE 广播解析。
///
/// 与参考实现 `VivoFastPairAdvertisementParser` 的差异说明：
/// 参考实现吃的是**完整 AD 结构**（含 `length` / AD type 字节），而 CoreBluetooth 的
/// `CBAdvertisementDataManufacturerDataKey` 只给厂商数据段（AD type 已被剥掉）。
/// 因此这里按 CoreBluetooth 的实际输入重写了偏移，并对短广播做宽容处理。
///
/// 本机实测样本（vivo TWS 5）：`37 08 08 01 aa bb cc 11 22 33`
/// → uuid `0x0837`、bleType `0x08`、版本 V1、随后 6 字节为 MAC `AA:BB:CC:11:22:33`。
public enum VivoFastPairAdvertisement {

    public static let uuidNew: UInt16 = 0x0837
    public static let uuidLegacy: UInt16 = 0x8486

    static let twsBleType: UInt8 = 0x08
    static let versionV1: UInt8 = 0x01
    static let versionV2: UInt8 = 0x02
    static let extendedModelMarker: UInt8 = 0xFF

    /// 解析 CoreBluetooth 给出的厂商数据段。
    public static func parse(_ bytes: [UInt8]) -> VivoFastPairIdentity? {
        // 至少要能读出 uuid(2) + bleType(1) + version(1)
        guard bytes.count >= 4 else { return nil }

        // 厂商 ID 为小端
        let uuid = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        guard uuid == uuidNew || uuid == uuidLegacy else { return nil }

        let bleType = bytes[2]
        guard bleType == twsBleType else { return nil }

        let version = bytes[3]
        guard version == versionV1 || version == versionV2 else { return nil }

        // 型号 id：对齐参考实现 packet_offset+17 → 厂商数据段内索引 15
        var modelId: Int?
        if bytes.count > 15 {
            let marker = bytes[15]
            if version == versionV2, marker == extendedModelMarker, bytes.count > 19 {
                // 扩展型号：小端 16 位
                modelId = Int(bytes[18]) | (Int(bytes[19]) << 8)
            } else {
                modelId = Int(marker)
            }
        }

        // 短布局里紧跟版本的 6 字节是 MAC
        var mac: String?
        if bytes.count >= 10 {
            mac = bytes[4..<10]
                .map { String(format: "%02X", $0) }
                .joined(separator: ":")
        }

        return VivoFastPairIdentity(
            uuid: uuid,
            bleType: bleType,
            protocolVersion: version,
            modelId: modelId,
            macAddress: mac
        )
    }
}

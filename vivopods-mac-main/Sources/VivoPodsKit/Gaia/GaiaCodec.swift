import Foundation

public enum GaiaCodecError: Error, Equatable, CustomStringConvertible {
    case payloadTooLong(Int)
    case frameTooShort(Int)

    public var description: String {
        switch self {
        case .payloadTooLong(let n):
            return "Compact GAIA payload 上限 254 字节，实际 \(n)"
        case .frameTooShort(let n):
            return "GATT 帧至少需要 4 字节 (vendor+command)，实际 \(n)"
        }
    }
}

/// GAIA 帧编码器。两种 wire format 共用同一套 vendor/command 常量。
///
/// `.classic` 部分与参考实现 `vivo/vivo_protocol.py` 的 `frame()` **逐字节对齐**，
/// 由移植过来的测试向量守护（见 `GaiaCodecTests`）。
public enum GaiaCodec {
    public static let preamble: UInt8 = 0xFF
    public static let flagChecksum: UInt8 = 0x01
    public static let flagLengthExtension: UInt8 = 0x02
    public static let commandBytes = 4
    public static let maxFrameBytes = 65_544
    /// Compact GAIA 的 payload 长度字段只有 1 字节，且参考实现固定拒绝 >254。
    public static let maxCompactPayload = 254

    /// 构造一帧。
    ///
    /// - Note: `.gatt` 忽略 `version` 与 `flags`（该封装无这两个字段）。
    public static func encode(
        version: UInt8,
        vendor: UInt16,
        command: UInt16,
        payload: [UInt8] = [],
        flags: UInt8 = 0,
        format: WireFormat
    ) throws -> [UInt8] {
        switch format {
        case .gatt:
            // 裸 content：GATT 自身提供长度与消息边界
            var out = [UInt8]()
            out.reserveCapacity(4 + payload.count)
            out.append(UInt8(truncatingIfNeeded: vendor >> 8))
            out.append(UInt8(truncatingIfNeeded: vendor))
            out.append(UInt8(truncatingIfNeeded: command >> 8))
            out.append(UInt8(truncatingIfNeeded: command))
            out.append(contentsOf: payload)
            return out

        case .classic:
            guard payload.count <= maxCompactPayload else {
                throw GaiaCodecError.payloadTooLong(payload.count)
            }
            let extended = (flags & flagLengthExtension) != 0
            let headerSize = extended ? 5 : 4

            var out = [UInt8](repeating: 0, count: headerSize + commandBytes + payload.count)
            out[0] = preamble
            out[1] = version
            out[2] = flags
            if extended {
                out[3] = UInt8(truncatingIfNeeded: payload.count >> 8)
                out[4] = UInt8(truncatingIfNeeded: payload.count)
            } else {
                out[3] = UInt8(truncatingIfNeeded: payload.count)
            }
            let voff = headerSize
            out[voff] = UInt8(truncatingIfNeeded: vendor >> 8)
            out[voff + 1] = UInt8(truncatingIfNeeded: vendor)
            out[voff + 2] = UInt8(truncatingIfNeeded: command >> 8)
            out[voff + 3] = UInt8(truncatingIfNeeded: command)
            if !payload.isEmpty {
                out.replaceSubrange((voff + commandBytes)..., with: payload)
            }
            if (flags & flagChecksum) != 0 {
                out.append(xor(out, out.count))
            }
            return out
        }
    }

    /// 对 `[0, count)` 区间做异或校验（对齐参考实现的 `_xor`）。
    static func xor(_ bytes: [UInt8], _ count: Int) -> UInt8 {
        var value: UInt8 = 0
        for i in 0..<min(count, bytes.count) {
            value ^= bytes[i]
        }
        return value
    }

    /// 解一条 `.gatt` 报文（一个 GATT 包 = 一帧，无需流式拆包）。
    public static func decodeGatt(_ bytes: [UInt8]) throws -> GaiaFrame {
        guard bytes.count >= 4 else {
            throw GaiaCodecError.frameTooShort(bytes.count)
        }
        return GaiaFrame(
            version: 0,
            flags: 0,
            vendor: UInt16(bytes[0]) << 8 | UInt16(bytes[1]),
            command: UInt16(bytes[2]) << 8 | UInt16(bytes[3]),
            payload: Array(bytes[4...]),
            raw: bytes
        )
    }
}

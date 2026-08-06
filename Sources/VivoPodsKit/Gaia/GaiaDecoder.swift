import Foundation

/// 流式 GAIA 解码器。
///
/// `.classic`（RFCOMM）是字节流，需要处理前导噪声、拆包与粘包；
/// `.gatt` 每个通知就是一帧，直接解。
///
/// `.classic` 逻辑与参考实现 `vivo/vivo_protocol.py` 的 `Decoder` 对齐，
/// 包括「校验失败则丢弃该帧并继续」的行为。
public final class GaiaDecoder {
    private let format: WireFormat
    private var buffer: [UInt8] = []

    public init(format: WireFormat) {
        self.format = format
    }

    public func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    /// 喂入新收到的字节，返回本次能完整解出的所有帧。
    public func offer(_ chunk: [UInt8]) -> [GaiaFrame] {
        switch format {
        case .gatt:
            // GATT 保留消息边界：一个包就是一帧，不入缓冲
            guard let frame = try? GaiaCodec.decodeGatt(chunk) else { return [] }
            return [frame]

        case .classic:
            buffer.append(contentsOf: chunk)
            return drainClassic()
        }
    }

    private func drainClassic() -> [GaiaFrame] {
        var frames: [GaiaFrame] = []

        while true {
            discardNoise()
            guard buffer.count >= 4 else { return frames }

            let flags = buffer[2]
            let extended = (flags & GaiaCodec.flagLengthExtension) != 0
            let headerSize = extended ? 5 : 4
            guard buffer.count >= headerSize else { return frames }

            let payloadLength: Int = extended
                ? Int(buffer[3]) << 8 | Int(buffer[4])
                : Int(buffer[3])
            let checksumBytes = (flags & GaiaCodec.flagChecksum) != 0 ? 1 : 0
            let total = headerSize + GaiaCodec.commandBytes + payloadLength + checksumBytes

            if total > GaiaCodec.maxFrameBytes {
                // 长度离谱 → 当前 FF 是噪声，前移一字节重新找帧头
                buffer.removeFirst(1)
                continue
            }
            guard buffer.count >= total else { return frames }

            let raw = Array(buffer[0..<total])
            buffer.removeFirst(total)

            if checksumBytes == 1, GaiaCodec.xor(raw, raw.count - 1) != raw[raw.count - 1] {
                // 校验不过：丢弃该帧，继续解后面的
                continue
            }

            let contentOffset = headerSize
            let payloadOffset = contentOffset + GaiaCodec.commandBytes
            frames.append(
                GaiaFrame(
                    version: raw[1],
                    flags: raw[2],
                    vendor: UInt16(raw[contentOffset]) << 8 | UInt16(raw[contentOffset + 1]),
                    command: UInt16(raw[contentOffset + 2]) << 8 | UInt16(raw[contentOffset + 3]),
                    payload: Array(raw[payloadOffset..<(payloadOffset + payloadLength)]),
                    raw: raw
                )
            )
        }
    }

    /// 丢弃帧头之前的噪声字节。
    private func discardNoise() {
        var count = 0
        while count < buffer.count && buffer[count] != GaiaCodec.preamble {
            count += 1
        }
        if count > 0 {
            buffer.removeFirst(count)
        }
    }
}

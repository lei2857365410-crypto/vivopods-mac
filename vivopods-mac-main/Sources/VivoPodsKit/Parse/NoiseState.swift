import Foundation

/// 降噪状态。
///
/// 两种来源帧共用同一 payload 布局 `status mode [noiseEffect] [transparencyEffect]`：
/// - `cmd=8230` 主动上报 / 查询结果（`acknowledged = false`）
/// - `cmd=8130` 设置后的确认（`acknowledged = true`）
public struct NoiseState: Sendable, Hashable {
    public let mode: NoiseMode
    public let noiseEffect: UInt8?
    public let transparencyEffect: UInt8?
    /// 是否为「设置确认」帧（而非查询上报）。
    public let acknowledged: Bool
    public let version: UInt8

    public init(
        mode: NoiseMode,
        noiseEffect: UInt8?,
        transparencyEffect: UInt8?,
        acknowledged: Bool,
        version: UInt8
    ) {
        self.mode = mode
        self.noiseEffect = noiseEffect
        self.transparencyEffect = transparencyEffect
        self.acknowledged = acknowledged
        self.version = version
    }

    public static func parse(_ frame: GaiaFrame) -> NoiseState? {
        guard frame.vendor == VivoGaia.vivoVendor else { return nil }
        guard frame.command == VivoGaia.Command.ackNoiseMode
                || frame.command == VivoGaia.Command.reportNoiseMode
        else { return nil }
        guard frame.payload.count >= 2, frame.payload[0] == 0 else { return nil }
        guard let mode = NoiseMode(rawValue: frame.payload[1]) else { return nil }

        return NoiseState(
            mode: mode,
            noiseEffect: frame.payload.count > 2 ? frame.payload[2] : nil,
            transparencyEffect: frame.payload.count > 3 ? frame.payload[3] : nil,
            acknowledged: frame.command == VivoGaia.Command.ackNoiseMode,
            version: frame.version
        )
    }
}

/// 握手结果。
public struct HandshakeState: Sendable, Hashable {
    public let accepted: Bool
    public let payload: [UInt8]
    public let version: UInt8

    public init(accepted: Bool, payload: [UInt8], version: UInt8) {
        self.accepted = accepted
        self.payload = payload
        self.version = version
    }

    /// 握手响应用的是 GAIA 标准 vendor `0x000A`，不是 vivo 私有 vendor。
    public static func parse(_ frame: GaiaFrame) -> HandshakeState? {
        guard frame.vendor == VivoGaia.gaiaVendor,
              frame.command == VivoGaia.Command.handshakeResponse
        else { return nil }

        return HandshakeState(
            accepted: frame.payload.first == 0,
            payload: frame.payload,
            version: frame.version
        )
    }
}

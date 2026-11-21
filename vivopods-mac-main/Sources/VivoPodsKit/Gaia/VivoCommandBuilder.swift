import Foundation

/// 按选定的 wire format 与机型 profile 构造 vivo 控制帧。
///
/// `.classic` 产出的字节与参考实现 `vivo/vivo_protocol.py` 的对应函数完全一致；
/// `.gatt` 产出同样的 `vendor+command+payload`，只是不加 `FF` 帧头。
public struct VivoCommandBuilder: Sendable {
    public let format: WireFormat
    public let profile: VivoProfile

    public init(format: WireFormat, profile: VivoProfile = .familyDefaultV4) {
        self.format = format
        self.profile = profile
    }

    /// 握手。注意用的是 GAIA 标准 vendor `0x000A`，版本固定 4。
    ///
    /// `.classic` → `FF 04 00 00 00 0A 03 00`
    public func handshake() throws -> [UInt8] {
        try GaiaCodec.encode(
            version: 4,
            vendor: VivoGaia.gaiaVendor,
            command: VivoGaia.Command.handshake,
            format: format
        )
    }

    /// 电量查询。参考实现此处版本固定 4（不随 profile 变）。
    ///
    /// `.classic` → `FF 04 00 00 00 1B 02 07`；`.gatt` → `00 1B 02 07`
    public func queryBattery() throws -> [UInt8] {
        try GaiaCodec.encode(
            version: 4,
            vendor: VivoGaia.vivoVendor,
            command: VivoGaia.Command.queryBattery,
            format: format
        )
    }

    /// 降噪状态查询。载荷随 profile 变（家族默认 v4 带一个 `00`）。
    public func queryNoiseMode() throws -> [UInt8] {
        try GaiaCodec.encode(
            version: profile.gaiaVersion,
            vendor: VivoGaia.vivoVendor,
            command: VivoGaia.Command.queryNoiseMode,
            payload: profile.noiseQueryPayload,
            format: format
        )
    }

    /// 设置降噪模式。载荷 = `[mode] + profile.noiseSetSuffix`。
    public func setNoiseMode(_ mode: NoiseMode) throws -> [UInt8] {
        try GaiaCodec.encode(
            version: profile.gaiaVersion,
            vendor: VivoGaia.vivoVendor,
            command: VivoGaia.Command.setNoiseMode,
            payload: [mode.rawValue] + profile.noiseSetSuffix,
            format: format
        )
    }

    /// 查询多连接设备列表。
    public func queryMultiConnectDevices() throws -> [UInt8] {
        try GaiaCodec.encode(
            version: profile.gaiaVersion,
            vendor: VivoGaia.vivoVendor,
            command: VivoGaia.Command.queryMultiConnectDevices,
            format: format
        )
    }

    /// 下发多连接设备列表。
    ///
    /// 官方 App 的做法是**全量下发**整张表（`W4/a.java` 里 `new byte[size * 7]`），
    /// 而不是发单台指令；要断开某台就把它的 `connectState` 置 0 后连整表一起发。
    public func setMultiConnectDevices(_ entries: [(mac: [UInt8], state: UInt8)]) throws -> [UInt8] {
        var payload: [UInt8] = []
        payload.reserveCapacity(entries.count * 7)
        for e in entries {
            // MAC 必须是 6 字节，否则整张表会错位
            guard e.mac.count == 6 else { throw GaiaCodecError.frameTooShort(e.mac.count) }
            payload.append(contentsOf: e.mac)
            payload.append(e.state)
        }
        return try GaiaCodec.encode(
            version: profile.gaiaVersion,
            vendor: VivoGaia.vivoVendor,
            command: VivoGaia.Command.setMultiConnectDevices,
            payload: payload,
            format: format
        )
    }

    /// 从耳机的多连接记录中移除某台设备。payload `[目标MAC:6][本机MAC:6]`
    public func removeMultiConnectDevice(
        target: [UInt8],
        localMac: [UInt8]
    ) throws -> [UInt8] {
        guard target.count == 6, localMac.count == 6 else {
            throw GaiaCodecError.frameTooShort(min(target.count, localMac.count))
        }
        return try GaiaCodec.encode(
            version: profile.gaiaVersion,
            vendor: VivoGaia.vivoVendor,
            command: VivoGaia.Command.removeMultiConnectDevice,
            payload: target + localMac,
            format: format
        )
    }

    /// 应答耳机的时间请求（耳机主动发 `0x8509`，主机回 `0x0509`）。
    ///
    /// 载荷是 7 字节纯二进制（非 BCD）：`[世纪, 年, 月, 日, 时, 分, 秒]`。
    /// 实测样本 `14 1a 08 06 0b 0c 1d` = 20,26,8,6,11,12,29 → 2026-08-06 11:12:29。
    public func replyPhoneTime(_ date: Date, calendar: Calendar = .current) throws -> [UInt8] {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = c.year ?? 2000
        let payload: [UInt8] = [
            UInt8(truncatingIfNeeded: year / 100),
            UInt8(truncatingIfNeeded: year % 100),
            UInt8(truncatingIfNeeded: c.month ?? 1),
            UInt8(truncatingIfNeeded: c.day ?? 1),
            UInt8(truncatingIfNeeded: c.hour ?? 0),
            UInt8(truncatingIfNeeded: c.minute ?? 0),
            UInt8(truncatingIfNeeded: c.second ?? 0),
        ]
        return try GaiaCodec.encode(
            version: 4,
            vendor: VivoGaia.vivoVendor,
            command: VivoGaia.Command.replyPhoneTime,
            payload: payload,
            format: format
        )
    }

    /// 调试台用：手工发任意帧。
    public func raw(
        vendor: UInt16,
        command: UInt16,
        payload: [UInt8] = [],
        version: UInt8? = nil
    ) throws -> [UInt8] {
        try GaiaCodec.encode(
            version: version ?? profile.gaiaVersion,
            vendor: vendor,
            command: command,
            payload: payload,
            format: format
        )
    }

    /// 连接后的初始读取序列。
    public func initialReadCommands() throws -> [[UInt8]] {
        [try handshake(), try queryNoiseMode(), try queryBattery()]
    }
}

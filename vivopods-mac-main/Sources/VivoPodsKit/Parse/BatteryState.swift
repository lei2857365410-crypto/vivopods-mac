import Foundation

/// 电量状态：左耳 / 右耳 / 充电盒，各带充电位。
///
/// 上报帧 `vendor=001B cmd=8207`，payload 布局 `status L R case flags`：
/// `flags` 的 bit0/1/2 分别是左耳/右耳/充电盒正在充电。
///
/// 参考实现测试向量：`… 82 07 | 00 5C 59 48 05`
/// → L=0x5C=92%、R=0x59=89%、仓=0x48=72%、flags=0x05 → 左耳与仓在充电。
public struct BatteryState: Sendable, Hashable {
    public let left: Int?
    public let right: Int?
    public let charging: Int?
    public let leftCharging: Bool
    public let rightCharging: Bool
    public let caseCharging: Bool
    public let version: UInt8

    public init(
        left: Int?,
        right: Int?,
        charging: Int?,
        leftCharging: Bool,
        rightCharging: Bool,
        caseCharging: Bool,
        version: UInt8
    ) {
        self.left = left
        self.right = right
        self.charging = charging
        self.leftCharging = leftCharging
        self.rightCharging = rightCharging
        self.caseCharging = caseCharging
        self.version = version
    }

    /// 充电盒电量（`charging` 字段的语义别名，避免与「正在充电」混淆）。
    public var caseLevel: Int? { charging }

    /// 状态栏要显示的数字：三者中最低的有效值。
    public var lowestLevel: Int? {
        [left, right, caseLevel].compactMap { $0 }.min()
    }

    /// 是否有任意部件正在充电（状态栏加 ⚡ 用）。
    public var anyCharging: Bool {
        leftCharging || rightCharging || caseCharging
    }

    /// 解析电量上报帧。非该命令或状态码非 0 时返回 `nil`。
    public static func parse(_ frame: GaiaFrame) -> BatteryState? {
        guard frame.vendor == VivoGaia.vivoVendor,
              frame.command == VivoGaia.Command.reportBattery,
              frame.payload.count >= 5,
              frame.payload[0] == 0
        else { return nil }

        let flags = frame.payload[4]
        func pct(_ b: UInt8) -> Int? {
            b <= 100 ? Int(b) : nil
        }

        return BatteryState(
            left: pct(frame.payload[1]),
            right: pct(frame.payload[2]),
            charging: pct(frame.payload[3]),
            leftCharging: flags & 0x01 != 0,
            rightCharging: flags & 0x02 != 0,
            caseCharging: flags & 0x04 != 0,
            version: frame.version
        )
    }
}

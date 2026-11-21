import Foundation

/// 一个部件的电量读数，附带「是否为缓存值」标记。
public struct BatteryReading: Sendable, Hashable {
    public let level: Int
    public let charging: Bool
    /// true 表示这不是最近一次上报里的实时值，而是此前记录下来的旧值。
    /// UI 应当据此把数字置灰，以免让人以为是当前状态。
    public let isStale: Bool

    public init(level: Int, charging: Bool, isStale: Bool) {
        self.level = level
        self.charging = charging
        self.isStale = isStale
    }
}

/// 电量缓存。
///
/// 耳机并不总是三个部件都上报有效值：耳塞戴在耳朵上时，充电盒那一字节是 `0xFF`
/// （无效）；断开连接后更是完全没有新数据。此时直接丢弃会让面板上的数字凭空消失，
/// 但把旧值当成实时值显示又会误导。
///
/// 所以这里记住每个部件**最后一次的有效读数**，并标记它是否来自最近一次上报。
public struct BatteryCache: Sendable {

    public enum Component: Sendable, Hashable, CaseIterable {
        case left, right, charging
    }

    private var stored: [Component: (level: Int, charging: Bool)] = [:]
    /// 最近一次上报中确实带有有效值的部件。
    private var fresh: Set<Component> = []

    public init() {}

    /// 吸收一次电量上报。
    ///
    /// 某部件这次没有有效值时，保留它此前的读数，但不再算作实时。
    public mutating func update(_ state: BatteryState) {
        apply(.left, level: state.left, charging: state.leftCharging)
        apply(.right, level: state.right, charging: state.rightCharging)
        apply(.charging, level: state.caseLevel, charging: state.caseCharging)
    }

    private mutating func apply(_ key: Component, level: Int?, charging: Bool) {
        if let level {
            stored[key] = (level: level, charging: charging)
            fresh.insert(key)
        } else {
            fresh.remove(key)
        }
    }

    /// 把所有读数标记为非实时（断开连接时调用）。
    ///
    /// 保留数值本身，这样面板仍能显示「上次看到的电量」，只是全部置灰。
    public mutating func markAllStale() {
        fresh.removeAll()
    }

    /// 彻底清空（换设备时调用，避免把上一台的电量显示给下一台）。
    public mutating func reset() {
        stored.removeAll()
        fresh.removeAll()
    }

    public func reading(_ key: Component) -> BatteryReading? {
        guard let v = stored[key] else { return nil }
        return BatteryReading(
            level: v.level,
            // 非实时数据的充电状态同样不可信，一并按「未充电」呈现，
            // 否则会出现「已断开却仍显示正在充电」这种自相矛盾的画面
            charging: fresh.contains(key) ? v.charging : false,
            isStale: !fresh.contains(key)
        )
    }

    public var left: BatteryReading? { reading(.left) }
    public var right: BatteryReading? { reading(.right) }
    public var charging: BatteryReading? { reading(.charging) }

    /// 是否一个读数都没有过。
    public var isEmpty: Bool { stored.isEmpty }

    /// 三者中最低的电量，用于菜单栏。只在有实时值时才返回，避免菜单栏显示旧数据。
    public var lowestFreshLevel: Int? {
        Component.allCases
            .filter { fresh.contains($0) }
            .compactMap { stored[$0]?.level }
            .min()
    }
}

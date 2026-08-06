import Foundation
import VivoPodsKit

/// 菜单栏文字的组装逻辑（与 `AppModel.statusText` 保持同一套规则）。
///
/// 单独在这里复刻一份纯函数版本来测：AppModel 依赖 AppKit/@MainActor，
/// 不便在自测可执行文件里实例化。规则一致性由这些断言守护。
func statusTextFor(_ b: BatteryState?) -> String {
    guard let b else { return "—" }
    var parts: [String] = []
    if let l = b.left { parts.append("L\(l)" + (b.leftCharging ? "⚡" : "")) }
    if let r = b.right { parts.append("R\(r)" + (b.rightCharging ? "⚡" : "")) }
    if parts.isEmpty, let c = b.caseLevel {
        parts.append("盒\(c)" + (b.caseCharging ? "⚡" : ""))
    }
    return parts.isEmpty ? "—" : parts.joined(separator: " ")
}

/// 复刻 `AppModel.shortDeviceName`：去空格、首字母大写、纯数字段保持原样。
func shortNameFor(_ raw: String) -> String {
    let compact = raw.split(separator: " ").map { seg -> String in
        if seg.allSatisfy(\.isNumber) { return String(seg) }
        return seg.prefix(1).uppercased() + seg.dropFirst().lowercased()
    }.joined()
    return compact.isEmpty ? "VivoPods" : compact
}

func runBatteryDisplayChecks() {
    Check.suite("菜单栏电量文字（左右分列 / 单侧省略）") {
        // 真机实测帧：耳机在用、不在盒中 → case = 0xFF 无效
        let both = BatteryState.parse(
            try GaiaCodec.decodeGatt(hx("00 1B 82 07 00 53 5C FF 00"))
        )
        Check.equal(statusTextFor(both), "L83 R92", "左右都有读数 → L83 R92")
        Check.isNil(both?.caseLevel, "0xFF 充电盒判为无效，不进菜单栏")

        // 只有左耳有读数（右耳在盒中/未上报）
        let leftOnly = BatteryState.parse(
            try GaiaCodec.decodeGatt(hx("00 1B 82 07 00 53 FF FF 00"))
        )
        Check.equal(statusTextFor(leftOnly), "L83", "只有左耳 → 只显示 L83")

        // 只有右耳
        let rightOnly = BatteryState.parse(
            try GaiaCodec.decodeGatt(hx("00 1B 82 07 00 FF 5C FF 00"))
        )
        Check.equal(statusTextFor(rightOnly), "R92", "只有右耳 → 只显示 R92")

        // 两耳都无读数但盒有 → 退回显示充电盒
        let caseOnly = BatteryState.parse(
            try GaiaCodec.decodeGatt(hx("00 1B 82 07 00 FF FF 48 00"))
        )
        Check.equal(statusTextFor(caseOnly), "盒72", "仅充电盒有读数 → 盒72")

        // 充电标记：flags 0x03 = 左右都在充电
        let charging = BatteryState.parse(
            try GaiaCodec.decodeGatt(hx("00 1B 82 07 00 53 5C FF 03"))
        )
        Check.equal(statusTextFor(charging), "L83⚡ R92⚡", "左右充电中各自带 ⚡")

        // 仅左耳充电
        let leftCharging = BatteryState.parse(
            try GaiaCodec.decodeGatt(hx("00 1B 82 07 00 53 5C FF 01"))
        )
        Check.equal(statusTextFor(leftCharging), "L83⚡ R92", "仅左耳充电 → 只有 L 带 ⚡")

        Check.equal(statusTextFor(nil), "—", "无数据时显示 —")
    }

    Check.suite("设备名紧凑化") {
        Check.equal(shortNameFor("vivo TWS 5"), "VivoTws5", "vivo TWS 5 → VivoTws5")
        Check.equal(shortNameFor("vivo TWS Air3 Pro"), "VivoTwsAir3Pro", "多段名去空格")
        Check.equal(shortNameFor("iQOO TWS 1"), "IqooTws1", "iQOO TWS 1 → IqooTws1")
        Check.equal(shortNameFor(""), "VivoPods", "空名回退为 VivoPods")
    }
}

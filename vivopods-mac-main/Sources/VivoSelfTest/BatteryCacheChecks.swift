import Foundation
import VivoPodsKit

func runBatteryCacheChecks() {
    Check.suite("电量缓存与过期标记") {
        var cache = BatteryCache()
        Check.ok(cache.isEmpty, "初始为空")
        Check.isNil(cache.left, "无数据时读不到")

        // 第一次上报：左右有效，仓为 0xFF（耳机不在盒中）
        let first = BatteryState.parse(
            try GaiaCodec.decodeGatt(hx("00 1B 82 07 00 53 5C FF 00"))
        )!
        cache.update(first)

        Check.equal(cache.left?.level, 83, "左耳 83%")
        Check.equal(cache.left?.isStale, false, "左耳为实时值")
        Check.equal(cache.right?.level, 92, "右耳 92%")
        Check.isNil(cache.charging, "仓从未有过有效值 → 读不到")
        Check.equal(cache.lowestFreshLevel, 83, "菜单栏取实时最低值 83")

        // 把耳机放回盒里：这次仓有值了
        cache.update(BatteryState.parse(
            try GaiaCodec.decodeGatt(hx("00 1B 82 07 00 53 5C 48 04"))
        )!)
        Check.equal(cache.charging?.level, 72, "仓 72%")
        Check.equal(cache.charging?.isStale, false, "仓为实时值")
        Check.equal(cache.charging?.charging, true, "仓正在充电（flags bit2）")

        // 再拿出来：仓又变 0xFF，应保留 72% 但标记为过期
        cache.update(BatteryState.parse(
            try GaiaCodec.decodeGatt(hx("00 1B 82 07 00 51 5A FF 00"))
        )!)
        Check.equal(cache.charging?.level, 72, "仓保留上次的 72%")
        Check.equal(cache.charging?.isStale, true, "仓标记为过期 → UI 置灰")
        Check.equal(cache.charging?.charging, false, "过期数据的充电状态不予呈现")
        Check.equal(cache.left?.level, 81, "左耳更新为 81%")
        Check.equal(cache.left?.isStale, false, "左耳仍是实时值")
        Check.equal(cache.lowestFreshLevel, 81, "最低实时值不含过期的仓")

        // 断开连接：数值全留，全部置灰
        cache.markAllStale()
        Check.equal(cache.left?.level, 81, "断开后仍能显示左耳最后读数")
        Check.equal(cache.left?.isStale, true, "断开后左耳置灰")
        Check.equal(cache.right?.isStale, true, "断开后右耳置灰")
        Check.isNil(cache.lowestFreshLevel, "断开后无实时值 → 菜单栏不显示旧数据")

        // 重新连上：恢复为实时
        cache.update(BatteryState.parse(
            try GaiaCodec.decodeGatt(hx("00 1B 82 07 00 50 59 FF 00"))
        )!)
        Check.equal(cache.left?.isStale, false, "重连后恢复实时标记")
        Check.equal(cache.left?.level, 80, "左耳 80%")

        // 换设备：彻底清空，避免把上一台的电量显示给下一台
        cache.reset()
        Check.ok(cache.isEmpty, "reset 后为空")
        Check.isNil(cache.right, "reset 后读不到任何值")
    }
}

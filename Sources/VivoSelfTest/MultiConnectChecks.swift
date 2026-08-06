import Foundation
import VivoPodsKit

/// 用**本机实测抓到的完整 0x8249 帧**做回归。
/// 这条数据同时验证了长度算术与 UTF-8 中文设备名解码。
func runMultiConnectChecks() {
    Check.suite("多连接设备列表解析（真机抓包）") {
        let raw = hx("""
        00 1b 82 49 00 03 \
        AA BB CC 44 55 66 38 01 0C 02 17 \
        E5 BC A0 E5 B0 8F E6 98 8E E7 9A 84 4D 61 63 42 6F 6F 6B 20 41 69 72 \
        DD EE FF 77 88 99 5A 02 0C 00 10 \
        E5 B0 8F E6 98 8E E7 9A 84 69 51 4F 4F 20 31 33 \
        11 22 33 AA BB CC 5A 41 1C 00 0D \
        69 51 4F 4F 20 50 61 64 32 20 50 72 6F
        """)

        let frame = try GaiaCodec.decodeGatt(raw)
        Check.equal(frame.payload.count, 87, "payload 长度 87（与真机 len 一致）")

        guard let devices = MultiConnectDevices.parse(frame) else {
            Check.ok(false, "应能解析出设备列表")
            return
        }
        Check.equal(devices.count, 3, "解析出 3 台设备")

        Check.equal(devices[0].macAddress, "AA:BB:CC:44:55:66", "设备1 MAC = 本机蓝牙控制器地址")
        Check.equal(devices[0].name, "张小明的MacBook Air", "设备1 名称（含中文）")
        Check.ok(devices[0].isConnected, "设备1 状态字节 0x02 → 已连接")

        Check.equal(devices[1].macAddress, "DD:EE:FF:77:88:99", "设备2 MAC")
        Check.equal(devices[1].name, "小明的iQOO 13", "设备2 名称")
        Check.ok(!devices[1].isConnected, "设备2 状态字节 0x00 → 未连接")

        Check.equal(devices[2].macAddress, "11:22:33:AA:BB:CC", "设备3 MAC")
        Check.equal(devices[2].name, "iQOO Pad2 Pro", "设备3 名称")
        Check.ok(!devices[2].isConnected, "设备3 未连接")

        // 名称长度字段与实际 UTF-8 字节数必须一致，否则解析会错位
        Check.equal(devices[0].name.utf8.count, 0x17, "设备1 名称 23 字节 = 长度字段 0x17")
        Check.equal(devices[1].name.utf8.count, 0x10, "设备2 名称 16 字节 = 长度字段 0x10")
        Check.equal(devices[2].name.utf8.count, 0x0D, "设备3 名称 13 字节 = 长度字段 0x0D")
    }
}

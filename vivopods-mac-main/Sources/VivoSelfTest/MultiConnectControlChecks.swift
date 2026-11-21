import Foundation
import VivoPodsKit

/// 多连接控制命令的编码检查。
///
/// 命令号与 payload 布局取自官方 Android APK 反编译（`W4/a.java`，DualConnectionManager）：
///   e(330, payload) → 0x014A 设置设备列表，payload 为 N×7 的 `[MAC:6][state:1]`
///   e(332, payload) → 0x014C 开关多连接
///   e(333, payload) → 0x014D 移除设备，payload `[目标MAC:6][本机MAC:6]`
/// 调用链 e→v→J→i(27, cmd, data)，其中 27=0x1B 是 vivo vendor，命令号无偏移。
func runMultiConnectControlChecks() {
    Check.suite("多连接控制编码（命令号源自 APK 反编译）") {
        let b = VivoCommandBuilder(format: .gatt)

        Check.equal(VivoGaia.Command.setMultiConnectDevices, 330, "330 == 0x014A 设置列表")
        Check.equal(VivoGaia.Command.setMultiConnectEnabled, 332, "332 == 0x014C 开关多连接")
        Check.equal(VivoGaia.Command.removeMultiConnectDevice, 333, "333 == 0x014D 移除设备")

        // 用真机抓到的那三台设备构造：断开 iQOO 13，保持本机连接
        let mac1: [UInt8] = [0xAA, 0xBB, 0xCC, 0x44, 0x55, 0x66]  // 本机 MacBook Air
        let mac2: [UInt8] = [0xDD, 0xEE, 0xFF, 0x77, 0x88, 0x99]  // iQOO 13
        let mac3: [UInt8] = [0x11, 0x22, 0x33, 0xAA, 0xBB, 0xCC]  // iQOO Pad2 Pro

        let payload = try b.setMultiConnectDevices([
            (mac: mac1, state: MultiConnectState.keep.rawValue),
            (mac: mac2, state: MultiConnectState.disconnect.rawValue),
            (mac: mac3, state: MultiConnectState.disconnect.rawValue),
        ])
        Check.equal(
            payload,
            hx("00 1B 01 4A "
               + "AA BB CC 44 55 66 01 "
               + "DD EE FF 77 88 99 00 "
               + "11 22 33 AA BB CC 00"),
            "全量下发 3 台，每台 7 字节"
        )
        Check.equal(payload.count, 4 + 21, "帧长 = 4 头 + 3×7")

        // 连接某台：state = 2
        let connect = try b.setMultiConnectDevices([
            (mac: mac2, state: MultiConnectState.connect.rawValue),
        ])
        Check.equal(connect, hx("00 1B 01 4A DD EE FF 77 88 99 02"), "connect 状态字节为 02")

        // 移除设备：目标 MAC + 本机 MAC
        Check.equal(
            try b.removeMultiConnectDevice(target: mac2, localMac: mac1),
            hx("00 1B 01 4D DD EE FF 77 88 99 AA BB CC 44 55 66"),
            "移除设备 payload = 目标MAC + 本机MAC"
        )

        // MAC 长度不对必须拒绝，否则整张表会错位
        Check.throwsError("MAC 非 6 字节应被拒绝") {
            _ = try b.setMultiConnectDevices([(mac: [0x01, 0x02], state: 0)])
        }

        // 解析出的 macBytes 应能还原回原始字节（往返一致）
        let frame = try GaiaCodec.decodeGatt(hx("""
        00 1b 82 49 00 03 \
        AA BB CC 44 55 66 38 01 0C 02 17 \
        E5 BC A0 E5 B0 8F E6 98 8E E7 9A 84 4D 61 63 42 6F 6F 6B 20 41 69 72 \
        DD EE FF 77 88 99 5A 02 0C 00 10 \
        E5 B0 8F E6 98 8E E7 9A 84 69 51 4F 4F 20 31 33 \
        11 22 33 AA BB CC 5A 41 1C 00 0D \
        69 51 4F 4F 20 50 61 64 32 20 50 72 6F
        """))
        guard let devices = MultiConnectDevices.parse(frame) else {
            Check.ok(false, "应能解析设备列表")
            return
        }
        Check.equal(devices[0].macBytes, mac1, "设备1 macBytes 往返一致")
        Check.equal(devices[1].macBytes, mac2, "设备2 macBytes 往返一致")
        Check.equal(devices[2].macBytes, mac3, "设备3 macBytes 往返一致")
    }
}

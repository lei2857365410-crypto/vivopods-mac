import Foundation
import VivoPodsKit

/// 编码向量逐条移植自参考实现 `TWS-Pods-PC/vivo/test_vivo.py`，
/// 用来保证 Swift 版与已验证的 Python 版**逐字节一致**。
func runClassicEncodeChecks() {
    Check.suite("RFCOMM/SPP 完整 GAIA 帧编码（对齐参考实现）") {
        let air3 = VivoCommandBuilder(format: .classic, profile: .air3ProCaptured)
        let v4 = VivoCommandBuilder(format: .classic, profile: .familyDefaultV4)
        let tws3e = VivoCommandBuilder(format: .classic, profile: .tws3eV3)

        Check.equal(
            try air3.setNoiseMode(.anc),
            hx("FF 03 00 03 00 1B 01 30 00 04 00"),
            "setNoiseMode(ANC, Air3Pro)"
        )
        Check.equal(
            try v4.setNoiseMode(.transparency),
            hx("FF 04 00 03 00 1B 01 30 02 03 01"),
            "setNoiseMode(通透, 家族默认v4)"
        )
        Check.equal(
            try tws3e.setNoiseMode(.off),
            hx("FF 03 00 02 00 1B 01 30 01 03"),
            "setNoiseMode(关闭, TWS3e)"
        )
        Check.equal(
            try air3.handshake(),
            hx("FF 04 00 00 00 0A 03 00"),
            "handshake 用 GAIA vendor 000A、版本固定 4"
        )
        Check.equal(
            try air3.queryNoiseMode(),
            hx("FF 03 00 00 00 1B 02 30"),
            "queryNoiseMode(Air3Pro) 空载荷"
        )
        Check.equal(
            try v4.queryNoiseMode(),
            hx("FF 04 00 01 00 1B 02 30 00"),
            "queryNoiseMode(家族默认v4) 载荷 00"
        )
        Check.equal(
            try air3.queryBattery(),
            hx("FF 04 00 00 00 1B 02 07"),
            "queryBattery 版本固定 4（不随 profile 变）"
        )

        Check.throwsError("payload 超过 254 字节应被拒绝") {
            _ = try GaiaCodec.encode(
                version: 4,
                vendor: VivoGaia.vivoVendor,
                command: 0x0207,
                payload: [UInt8](repeating: 0, count: 255),
                format: .classic
            )
        }
    }
}

/// `.gatt` 封装：同样的 vendor+command+payload，但没有 `FF` 帧头。
func runGattEncodeChecks() {
    Check.suite("BLE GATT 裸 content 编码") {
        let g = VivoCommandBuilder(format: .gatt)

        Check.equal(try g.queryBattery(), hx("00 1B 02 07"), "queryBattery 无帧头")
        Check.equal(try g.handshake(), hx("00 0A 03 00"), "handshake 无帧头")
        Check.equal(
            try VivoCommandBuilder(format: .gatt, profile: .familyDefaultV4)
                .setNoiseMode(.transparency),
            hx("00 1B 01 30 02 03 01"),
            "setNoiseMode 无帧头"
        )

        // GATT 没有 1 字节长度字段，因此不受 254 限制
        let long = try GaiaCodec.encode(
            version: 0,
            vendor: VivoGaia.vivoVendor,
            command: 0x0207,
            payload: [UInt8](repeating: 0xAB, count: 300),
            format: .gatt
        )
        Check.equal(long.count, 304, "GATT 允许长载荷（4 + 300）")
    }
}

/// 这些是**本机实测抓包**（vivo iOS 版 App 的 BLE GATT 通道），
/// 作为「`.gatt` 无帧头」这一结论的回归保护。
func runRealCaptureChecks() {
    Check.suite("真机抓包回归（vivo iOS App 的 GATT 帧）") {
        let req = try GaiaCodec.decodeGatt(hx("00 1b 85 09 00"))
        Check.equal(req.vendor, VivoGaia.vivoVendor, "抓包帧 vendor = 001B")
        Check.equal(req.command, VivoGaia.Command.requestPhoneTime, "cmd = 8509 索要手机时间")
        Check.ok(req.isResponse, "0x8509 带响应位")
        Check.equal(req.baseCommand, 0x0509, "去掉响应位 = 0x0509")

        let reply = try GaiaCodec.decodeGatt(hx("00 1b 05 09 14 1a 08 06 0b 0c 1d"))
        Check.equal(reply.command, VivoGaia.Command.replyPhoneTime, "cmd = 0509 应答")
        Check.equal(reply.payload, [20, 26, 8, 6, 11, 12, 29], "时间载荷 = 2026-08-06 11:12:29")

        // 我们自己构造的应答，应与官方 App 抓到的字节完全一致
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 6
        comps.hour = 11; comps.minute = 12; comps.second = 29
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = cal.date(from: comps)!
        Check.equal(
            try VivoCommandBuilder(format: .gatt).replyPhoneTime(date, calendar: cal),
            hx("00 1b 05 09 14 1a 08 06 0b 0c 1d"),
            "自建时间应答与官方 App 字节一致"
        )

        let multi = try GaiaCodec.decodeGatt(hx("00 1b 82 49 00 03 fc b2"))
        Check.equal(multi.command, VivoGaia.Command.reportMultiConnectDevices, "cmd = 8249 多连接设备列表")
        Check.equal(multi.baseCommand, VivoGaia.Command.queryMultiConnectDevices, "对应请求 0x0249")
        Check.ok(multi.isSuccess, "payload[0] = 00 表示成功")
    }
}

import Foundation
import VivoPodsKit

func runDecoderChecks() {
    Check.suite("流式解码器（拆包 / 粘包 / 噪声）") {
        let dec = GaiaDecoder(format: .classic)
        // 前导噪声 11 22 应丢弃；剩余不足一帧
        Check.equal(dec.offer(hx("11 22 FF 03 00 04 00 1B")).count, 0, "半帧不产出")
        let frames = dec.offer(hx("82 30 00 02 04 00"))
        Check.equal(frames.count, 1, "补齐后解出 1 帧")

        if let s = NoiseState.parse(frames[0]) {
            Check.equal(s.mode, .transparency, "跨包帧解析出通透模式")
            Check.equal(s.noiseEffect, 4, "noiseEffect = 4")
            Check.equal(s.transparencyEffect, 0, "transparencyEffect = 0")
            Check.ok(!s.acknowledged, "8230 是上报而非确认")
        } else {
            Check.ok(false, "跨包帧应能解析为降噪状态")
        }

        let multi = GaiaDecoder(format: .classic).offer(hx(
            "FF 03 00 04 00 1B 82 30 00 01 04 00 " +
            "FF 03 00 05 00 1B 82 07 00 53 52 FF 00 " +
            "FF 03 00 02 00 1B 82 0D 00 04"
        ))
        Check.equal(multi.count, 3, "粘包切出 3 帧")
        Check.equal(multi[0].command, VivoGaia.Command.reportNoiseMode, "第 1 帧 = 8230")
        Check.equal(multi[1].command, VivoGaia.Command.reportBattery, "第 2 帧 = 8207")
        Check.equal(multi[2].command, 0x820D, "第 3 帧未知命令 820D 也照样切出")

        // 充电盒 0xFF 超出 0..100 → 判为无效
        let batt = BatteryState.parse(multi[1])
        Check.equal(batt?.left, 83, "左耳 83%")
        Check.equal(batt?.right, 82, "右耳 82%")
        Check.isNil(batt?.caseLevel, "充电盒 0xFF 视为无效")

        let gattFrames = GaiaDecoder(format: .gatt).offer(hx("00 1B 82 07 00 5C 59 48 05"))
        Check.equal(gattFrames.count, 1, "GATT 一包即一帧")
        Check.equal(gattFrames[0].command, VivoGaia.Command.reportBattery, "GATT 电量帧")
    }
}

func runBatteryChecks() {
    Check.suite("电量解析") {
        let frame = GaiaDecoder(format: .classic)
            .offer(hx("FF 03 00 05 00 1B 82 07 00 5C 59 48 05"))[0]
        guard let b = BatteryState.parse(frame) else {
            Check.ok(false, "应能解析电量帧")
            return
        }
        Check.equal(b.left, 92, "左耳 0x5C = 92%")
        Check.equal(b.right, 89, "右耳 0x59 = 89%")
        Check.equal(b.caseLevel, 72, "充电盒 0x48 = 72%")
        Check.ok(b.leftCharging, "flags bit0 → 左耳充电中")
        Check.ok(!b.rightCharging, "flags bit1 = 0 → 右耳未充电")
        Check.ok(b.caseCharging, "flags bit2 → 充电盒充电中")
        Check.equal(b.lowestLevel, 72, "状态栏取最低值 72")
        Check.ok(b.anyCharging, "存在充电中部件")

        let noiseFrame = GaiaDecoder(format: .classic)
            .offer(hx("FF 03 00 04 00 1B 82 30 00 01 04 00"))[0]
        Check.isNil(BatteryState.parse(noiseFrame), "非电量命令不误解析")
    }
}

func runNoiseChecks() {
    Check.suite("降噪解析") {
        let report = GaiaDecoder(format: .classic)
            .offer(hx("FF 03 00 04 00 1B 82 30 00 01 04 00"))[0]
        Check.equal(NoiseState.parse(report)?.mode, .off, "8230 上报：关闭")
        Check.equal(NoiseState.parse(report)?.acknowledged, false, "上报帧 acknowledged = false")

        let ack = GaiaDecoder(format: .classic)
            .offer(hx("FF 03 00 03 00 1B 81 30 00 02 03"))[0]
        Check.equal(NoiseState.parse(ack)?.mode, .transparency, "8130 确认：通透")
        Check.equal(NoiseState.parse(ack)?.noiseEffect, 3, "noiseEffect = 3")
        Check.isNil(NoiseState.parse(ack)?.transparencyEffect, "该帧无 transparencyEffect")
        Check.equal(NoiseState.parse(ack)?.acknowledged, true, "确认帧 acknowledged = true")

        let bogus = GaiaDecoder(format: .classic)
            .offer(hx("FF 03 00 02 00 1B 82 30 00 09"))[0]
        Check.isNil(NoiseState.parse(bogus), "未知 mode 0x09 不解析")
    }
}

func runHandshakeChecks() {
    Check.suite("握手解析") {
        let hs = GaiaDecoder(format: .classic)
            .offer(hx("FF 03 00 04 00 0A 83 00 00 03 03 01"))[0]
        Check.equal(HandshakeState.parse(hs)?.accepted, true, "握手被接受")
        Check.equal(HandshakeState.parse(hs)?.version, 3, "版本 3")

        let batt = GaiaDecoder(format: .classic)
            .offer(hx("FF 03 00 05 00 1B 82 07 00 53 52 5F 00"))[0]
        Check.isNil(HandshakeState.parse(batt), "vivo vendor 帧不当作握手")
    }
}

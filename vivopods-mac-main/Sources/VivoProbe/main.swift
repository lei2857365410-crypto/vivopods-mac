import Foundation
import VivoPodsKit

// ─────────────────────────────────────────────────────────────
// vivo TWS 协议探测工具
//
// 目的：在写 GUI 之前，先用真机确认哪些命令真的有回包。
// 协议是逆向来的，参考实现的电量/降噪命令号取自 Air3 Pro / TWS 3e 的 RFCOMM 抓包，
// 本机是 vivo TWS 5 且走 BLE GATT，必须实测才能当真。
// ─────────────────────────────────────────────────────────────

struct Options {
    var seconds: Double = 25
    var name: String?
    var profile: VivoProfile = .familyDefaultV4
    var setNoise: NoiseMode?
    var rawHex: [String] = []
    var verbose = false
}

func parseArgs() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        switch arg {
        case "--seconds", "-t":
            if let v = it.next(), let d = Double(v) { o.seconds = d }
        case "--name", "-n":
            o.name = it.next()
        case "--profile", "-p":
            switch it.next() {
            case "air3": o.profile = .air3ProCaptured
            case "tws3e": o.profile = .tws3eV3
            default: o.profile = .familyDefaultV4
            }
        case "--set-noise":
            switch it.next() {
            case "anc": o.setNoise = .anc
            case "off": o.setNoise = .off
            case "transparency", "trans": o.setNoise = .transparency
            default: break
            }
        case "--raw":
            if let v = it.next() { o.rawHex.append(v) }
        case "--verbose", "-v":
            o.verbose = true
        case "--help", "-h":
            print("""
            用法：vivoprobe [选项]

              -t, --seconds N       运行时长（默认 25 秒）
              -n, --name NAME       只连指定名称的设备
              -p, --profile P       wire profile: v4(默认) | air3 | tws3e
                  --set-noise M     实测降噪设置: anc | off | transparency
                  --raw HEX         额外发送一帧原始 content（如 001B0207），可重复
              -v, --verbose         打印原始收发字节
            """)
            exit(0)
        default:
            break
        }
    }
    return o
}

func hexToBytes(_ text: String) -> [UInt8] {
    let compact = text.replacingOccurrences(of: " ", with: "")
    var out: [UInt8] = []
    var i = compact.startIndex
    while i < compact.endIndex, compact.index(i, offsetBy: 2, limitedBy: compact.endIndex) != nil {
        let n = compact.index(i, offsetBy: 2)
        guard let b = UInt8(compact[i..<n], radix: 16) else { break }
        out.append(b)
        i = n
    }
    return out
}

func stamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

// ─────────────────────────────────────────────────────────────

let opts = parseArgs()
let builder = VivoCommandBuilder(format: .gatt, profile: opts.profile)
let transport = BLETransport(preferredName: opts.name)

/// 记录每类命令是否收到过回包，最后给结论。
final class Outcome {
    var handshake = false
    var battery = false
    var noise = false
    var multiConnect = false
    var frameCount = 0
    var unknownCommands = Set<UInt16>()
}
let outcome = Outcome()

print("vivo TWS 协议探测")
print(String(repeating: "═", count: 58))
print("通道    : BLE GATT (裸 content)")
print("Profile : \(opts.profile.label)  — \(opts.profile.note)")
print("时长    : \(opts.seconds) 秒")
print(String(repeating: "─", count: 58))

transport.onLog = { msg in
    print("[\(stamp())] \(msg)")
}

transport.onRawOut = { bytes in
    if opts.verbose {
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("[\(stamp())]   →  \(hex)")
    }
}

transport.onRawIn = { bytes in
    if opts.verbose {
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("[\(stamp())]   ←  \(hex)")
    }
}

transport.onFrame = { frame in
    outcome.frameCount += 1

    // 1) 耳机主动索要手机时间 → 必须应答，否则它可能不继续交互
    if frame.command == VivoGaia.Command.requestPhoneTime {
        print("[\(stamp())] ◀ 耳机索要手机时间 (0x8509) → 应答")
        if let reply = try? builder.replyPhoneTime(Date()) {
            transport.send(reply)
        }
        return
    }

    // 2) 已知结构化状态
    if let hs = HandshakeState.parse(frame) {
        outcome.handshake = true
        print("[\(stamp())] ◀ 握手响应：\(hs.accepted ? "接受" : "拒绝")  版本 \(hs.version)")
        return
    }
    if let b = BatteryState.parse(frame) {
        outcome.battery = true
        let f: (Int?) -> String = { $0.map { "\($0)%" } ?? "—" }
        print("[\(stamp())] ◀ 电量：左 \(f(b.left))\(b.leftCharging ? "⚡" : "")  "
              + "右 \(f(b.right))\(b.rightCharging ? "⚡" : "")  "
              + "仓 \(f(b.caseLevel))\(b.caseCharging ? "⚡" : "")")
        return
    }
    if let n = NoiseState.parse(frame) {
        outcome.noise = true
        print("[\(stamp())] ◀ 降噪：\(n.mode.displayName)"
              + "  \(n.acknowledged ? "(设置确认)" : "(状态上报)")"
              + "  effect=\(n.noiseEffect.map(String.init) ?? "—")")
        return
    }

    // 3) 多连接设备列表：尾部常带 ASCII 设备名
    if frame.command == VivoGaia.Command.reportMultiConnectDevices {
        outcome.multiConnect = true
        print("[\(stamp())] ◀ 多连接设备列表 (0x8249) len=\(frame.payload.count)")
        if let devices = MultiConnectDevices.parse(frame) {
            for d in devices {
                let flags = d.unknownFlags.map { String(format: "%02X", $0) }.joined(separator: " ")
                print("           · \(d.name)")
                print("             \(d.macAddress)   \(d.stateLabel)"
                      + "  (状态字节 \(String(format: "%02X", d.stateByte))，未知位 \(flags))")
            }
        } else {
            print("           解析失败，原始 hex: \(frame.hexPayload)")
        }
        return
    }

    // 4) 埋点上报，吸收即可
    if frame.command == VivoGaia.Command.reportTracking {
        let json = String(bytes: frame.payload.filter { $0 >= 0x20 && $0 < 0x7F }, encoding: .ascii) ?? ""
        print("[\(stamp())] ◀ 耳机埋点上报 (0x8224) \(json.prefix(80))")
        return
    }

    // 5) 未知命令：原样记录，这是继续逆向的线索
    outcome.unknownCommands.insert(frame.command)
    print("[\(stamp())] ◀ 未知帧 cmd=\(String(format: "%04X", frame.command)) "
          + "len=\(frame.payload.count)  \(frame.hexPayload)")
}

transport.onStateChange = { state in
    print("[\(stamp())] 状态：\(state.label)")

    guard state.isReady else { return }

    // 通道就绪后按序发探测命令，每条之间留出回包时间
    var delay = 0.0
    func schedule(_ label: String, _ make: () throws -> [UInt8]) {
        guard let bytes = try? make() else { return }
        delay += 1.2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("[\(stamp())] ▶ \(label)  \(hex)")
            transport.send(bytes)
        }
    }

    schedule("握手 (000A 0300)") { try builder.handshake() }
    schedule("查询电量 (001B 0207)") { try builder.queryBattery() }
    schedule("查询降噪 (001B 0230)") { try builder.queryNoiseMode() }
    schedule("查询多连接设备 (001B 0249)") { try builder.queryMultiConnectDevices() }

    if let mode = opts.setNoise {
        schedule("设置降噪=\(mode.displayName) (001B 0130)") { try builder.setNoiseMode(mode) }
        schedule("回读降噪 (001B 0230)") { try builder.queryNoiseMode() }
    }
    for hex in opts.rawHex {
        let bytes = hexToBytes(hex)
        guard !bytes.isEmpty else { continue }
        schedule("原始帧") { bytes }
    }
}

transport.start()

RunLoop.main.run(until: Date().addingTimeInterval(opts.seconds))
transport.stop()

// ─────────────────────────────────────────────────────────────

print("\n" + String(repeating: "═", count: 58))
print("探测结论")
print(String(repeating: "─", count: 58))
print("收到帧总数        : \(outcome.frameCount)")
func mark(_ ok: Bool) -> String { ok ? "✓ 有回包" : "✗ 无回包" }
print("握手 0x0300       : \(mark(outcome.handshake))")
print("电量 0x0207       : \(mark(outcome.battery))")
print("降噪 0x0230       : \(mark(outcome.noise))")
print("多连接 0x0249     : \(mark(outcome.multiConnect))")
if !outcome.unknownCommands.isEmpty {
    let list = outcome.unknownCommands.sorted().map { String(format: "%04X", $0) }
    print("未知命令（线索）  : \(list.joined(separator: ", "))")
}
if outcome.frameCount == 0 {
    print("\n一帧都没收到。可能原因：")
    print("  · 该机型在 BLE 通道上不接受这些命令 → 试 RFCOMM/SPP 通道")
    print("  · 耳机需要先与 Mac 建立经典蓝牙连接（确认已连上并在使用）")
    print("  · 官方 App 正占用该通道 → 先退出 vEarphones")
}

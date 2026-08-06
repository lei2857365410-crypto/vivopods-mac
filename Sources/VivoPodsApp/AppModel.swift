import Foundation
import SwiftUI
import VivoPodsKit

struct LogLine: Identifiable {
    let id = UUID()
    let time: String
    let text: String
    let hex: String?
    let outgoing: Bool
}

@MainActor
final class AppModel: ObservableObject {

    @Published var state: TransportState = .idle
    @Published var battery: BatteryState?
    @Published var noise: NoiseState?
    @Published var devices: [MultiConnectDevice] = []
    @Published var logLines: [LogLine] = []
    @Published var showDebug = false
    /// 设置降噪后先乐观更新，等确认帧回来再校正。
    @Published var pendingNoiseMode: NoiseMode?
    /// 开机自启状态。面板要据此打勾，所以做成 @Published 而不是每次读系统。
    @Published var launchAtLogin = LoginItem.isEnabled
    @Published var launchAtLoginNeedsApproval = LoginItem.requiresApproval

    /// 由 StatusBarController 注入：打开调试台窗口。
    var openDebugConsole: (() -> Void)?

    private var session: EarbudSession?
    private var refreshTimer: Timer?
    private var reconnectTimer: Timer?

    init() {
        // 必须在这里启动，不能放在 PopoverView 的 onAppear：
        // MenuBarExtra 的内容视图只有用户点开弹窗时才创建，那样不点开就永远不连接，
        // 状态栏也就一直是「—」。
        start()
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - 状态栏展示

    /// 菜单栏文字：`L84 R93` 形式，充电中在对应数字后加 ⚡。
    ///
    /// 只有一侧有读数时就只显示那一侧（单只耳机在用、或另一只在盒中）；
    /// 两只都没有则退回显示充电盒。
    var statusText: String {
        guard state.isReady else { return "—" }
        guard let b = battery else { return "—" }

        var parts: [String] = []
        if let l = b.left {
            parts.append("L\(l)" + (b.leftCharging ? "⚡" : ""))
        }
        if let r = b.right {
            parts.append("R\(r)" + (b.rightCharging ? "⚡" : ""))
        }
        if parts.isEmpty, let c = b.caseLevel {
            parts.append("盒\(c)" + (b.caseCharging ? "⚡" : ""))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    var statusSymbol: String { "airpods.gen3" }

    /// 菜单栏用的紧凑设备名：去掉空格，如 "vivo TWS 5" → "VivoTws5"。
    var shortDeviceName: String {
        guard case .ready(let raw) = state else { return "VivoPods" }
        let compact = raw.split(separator: " ").map { seg -> String in
            // 纯数字段保持原样，其余首字母大写、其余小写
            if seg.allSatisfy(\.isNumber) { return String(seg) }
            return seg.prefix(1).uppercased() + seg.dropFirst().lowercased()
        }.joined()
        return compact.isEmpty ? "VivoPods" : compact
    }

    /// 电量偏低时把菜单栏文字染色提醒。
    var statusIsLow: Bool {
        guard let level = battery?.lowestLevel else { return false }
        return level < 20 && battery?.anyCharging != true
    }

    var deviceTitle: String {
        if case .ready(let name) = state { return name }
        return "vivo 耳机"
    }

    /// 当前应高亮的降噪模式（乐观值优先）。
    var effectiveNoiseMode: NoiseMode? {
        pendingNoiseMode ?? noise?.mode
    }

    // MARK: - 生命周期

    func start() {
        guard session == nil else { return }

        let transport = BLETransport()
        let s = EarbudSession(transport: transport)
        session = s

        s.onStateChange = { [weak self] st in
            Task { @MainActor in
                guard let self else { return }
                self.state = st
                self.append("状态：\(st.label)", hex: nil, outgoing: false)
                if st.isReady {
                    self.session?.refresh()
                    self.startRefreshTimer()
                } else {
                    self.stopRefreshTimer()
                    if case .disconnected = st {
                        self.battery = nil
                        self.devices = []
                        // 菜单栏图标在未连接时是隐藏的，若不自动重连，
                        // 耳机再次连上后图标不会回来，用户也没有入口能操作。
                        self.scheduleReconnect()
                    }
                }
            }
        }

        s.onBattery = { [weak self] b in
            Task { @MainActor in self?.battery = b }
        }

        s.onNoise = { [weak self] n in
            Task { @MainActor in
                self?.noise = n
                // 确认帧回来后撤销乐观值
                if n.acknowledged || self?.pendingNoiseMode == n.mode {
                    self?.pendingNoiseMode = nil
                }
            }
        }

        s.onDevices = { [weak self] list in
            Task { @MainActor in self?.devices = list }
        }

        s.onLog = { [weak self] msg in
            Task { @MainActor in
                // 会话层用 "▶ " 前缀标记发出的命令；这里剥掉，方向由 outgoing 表达，
                // 否则调试台会出现 "▶ ▶ 握手" 这样的双箭头
                let outgoing = msg.hasPrefix("▶")
                let text = outgoing
                    ? String(msg.dropFirst()).trimmingCharacters(in: .whitespaces)
                    : msg
                self?.append(text, hex: nil, outgoing: outgoing)
            }
        }

        s.onFrame = { [weak self] frame, note in
            Task { @MainActor in
                self?.append(
                    "\(String(format: "%04X", frame.command))  \(note)",
                    hex: frame.hexPayload,
                    outgoing: false
                )
            }
        }

        s.start()
    }

    func refresh() {
        session?.refresh()
    }

    func setNoise(_ mode: NoiseMode) {
        pendingNoiseMode = mode
        session?.setNoiseMode(mode)
        // 稍后回读校正
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.session?.refresh()
        }
    }

    /// 切换开机自启。
    func toggleLaunchAtLogin() {
        if LoginItem.requiresApproval {
            LoginItem.openSystemSettings()
            return
        }
        let result = LoginItem.setEnabled(!LoginItem.isEnabled)
        if !result.ok {
            append("设置开机启动失败：\(result.message ?? "未知错误")", hex: nil, outgoing: false)
        }
        launchAtLogin = LoginItem.isEnabled
        launchAtLoginNeedsApproval = LoginItem.requiresApproval
    }

    /// 切换/断开多连接设备。命令号 `0x014A` 取自官方 APK 反编译。
    func toggleDevice(_ device: MultiConnectDevice) {
        // 当前这台 Mac 自己不允许断开——断了就再也发不出命令了
        if device.isConnected, isSelf(device) {
            append("「\(device.name)」是当前主机，不能断开自己", hex: nil, outgoing: false)
            return
        }
        session?.setDeviceConnected(device, connected: !device.isConnected)
    }

    var canControlDevices: Bool { state.isReady }

    /// 判断某条记录是否就是本机。
    ///
    /// 依据：设备表里本机那条的 MAC 与 Mac 蓝牙控制器地址一致
    /// （实测 `FC:B2:14:51:93:7D` 同时出现在设备表与 `system_profiler` 中）。
    func isSelf(_ device: MultiConnectDevice) -> Bool {
        device.macAddress.caseInsensitiveCompare(localControllerMac ?? "") == .orderedSame
    }

    /// 本机蓝牙控制器地址，用于识别设备表里的「自己」。
    private lazy var localControllerMac: String? = Self.readLocalControllerMac()

    private static func readLocalControllerMac() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            // 首个 "Address: XX:XX:.." 是控制器自身地址
            for line in text.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("Address:") else { continue }
                return t.replacingOccurrences(of: "Address:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .uppercased()
            }
        } catch {
            return nil
        }
        return nil
    }

    func sendRaw(hex: String) {
        let compact = hex.replacingOccurrences(of: " ", with: "")
        var bytes: [UInt8] = []
        var i = compact.startIndex
        while i < compact.endIndex,
              let n = compact.index(i, offsetBy: 2, limitedBy: compact.endIndex) {
            guard let b = UInt8(compact[i..<n], radix: 16) else { break }
            bytes.append(b)
            i = n
        }
        guard !bytes.isEmpty else { return }
        append("手动发送", hex: bytes.map { String(format: "%02X", $0) }.joined(separator: " "),
               outgoing: true)
        session?.sendRaw(bytes)
    }

    func quit() {
        shutdown()
        NSApplication.shared.terminate(nil)
    }

    /// 断开蓝牙并停掉定时器。退出前调用，避免留下悬挂的 CoreBluetooth 会话。
    func shutdown() {
        stopRefreshTimer()
        session?.stop()
    }

    // MARK: - 内部

    /// 断开后周期性重试连接，直到成功。
    ///
    /// 耳机进盒 / 走出范围都会断开，恢复时 CoreBluetooth 不会主动通知，
    /// 必须自己重新 `retrieveConnectedPeripherals` + connect。
    private func scheduleReconnect() {
        guard reconnectTimer == nil else { return }
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.state.isReady {
                    self.reconnectTimer?.invalidate()
                    self.reconnectTimer = nil
                    return
                }
                self.session?.start()
            }
        }
    }

    private func startRefreshTimer() {
        stopRefreshTimer()
        // 电量变化慢，30 秒一次足够，避免频繁唤醒耳机
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.session?.refresh() }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// 设 `VIVOPODS_VERBOSE=1` 时把调试台内容同时打到 stdout，
    /// 便于从终端直接跑 bundle 内的可执行文件排查问题。
    private static let verbose = ProcessInfo.processInfo.environment["VIVOPODS_VERBOSE"] == "1"

    private func append(_ text: String, hex: String?, outgoing: Bool) {
        if Self.verbose {
            let arrow = outgoing ? "▶" : "◀"
            print("\(Self.timeFormatter.string(from: Date())) \(arrow) \(text)"
                  + (hex.map { $0.isEmpty ? "" : "  [\($0)]" } ?? ""))
            fflush(stdout)
        }
        logLines.append(
            LogLine(
                time: Self.timeFormatter.string(from: Date()),
                text: text,
                hex: hex,
                outgoing: outgoing
            )
        )
        if logLines.count > 300 {
            logLines.removeFirst(logLines.count - 300)
        }
    }
}

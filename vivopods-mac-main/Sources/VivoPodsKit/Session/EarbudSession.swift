import Foundation

/// 会话编排：把传输层收到的帧翻译成结构化状态，并负责耳机主动请求的应答。
///
/// 不含任何 UI 依赖，便于在 CLI 与 App 之间复用。
public final class EarbudSession {

    public let transport: EarbudTransport
    public private(set) var builder: VivoCommandBuilder

    // 最近一次已知状态
    public private(set) var battery: BatteryState?
    public private(set) var noise: NoiseState?
    public private(set) var devices: [MultiConnectDevice] = []
    public private(set) var handshakeAccepted: Bool?
    public private(set) var deviceName: String?

    // 回调
    public var onBattery: ((BatteryState) -> Void)?
    public var onNoise: ((NoiseState) -> Void)?
    public var onDevices: (([MultiConnectDevice]) -> Void)?
    public var onHandshake: ((Bool) -> Void)?
    public var onStateChange: ((TransportState) -> Void)?
    public var onLog: ((String) -> Void)?
    /// 调试台：每一帧（含未知帧）都会回调，附带一句人类可读说明。
    public var onFrame: ((GaiaFrame, String) -> Void)?

    /// 是否自动应答耳机的时间请求。关掉会导致部分机型停止后续交互。
    public var autoReplyPeerRequests = true

    public init(transport: EarbudTransport, profile: VivoProfile = .familyDefaultV4) {
        self.transport = transport
        self.builder = VivoCommandBuilder(format: transport.format, profile: profile)
        wire()
    }

    // MARK: - 生命周期

    public func start() {
        transport.start()
    }

    public func stop() {
        transport.stop()
    }

    /// 连接就绪后的初始读取；也可随时手动调用刷新。
    public func refresh() {
        send(try? builder.handshake(), "握手")
        send(try? builder.queryBattery(), "查询电量")
        send(try? builder.queryNoiseMode(), "查询降噪")
        send(try? builder.queryMultiConnectDevices(), "查询多连接设备")
    }

    public func setNoiseMode(_ mode: NoiseMode) {
        send(try? builder.setNoiseMode(mode), "设置降噪=\(mode.displayName)")
    }

    /// 把某台多连接设备切换为「连接」或「断开」。
    ///
    /// 按官方 App 的语义**全量下发**整张表（见 `VivoCommandBuilder.setMultiConnectDevices`）：
    /// 目标设备取新状态，其余设备保持原状。只发单台会被耳机理解为「表里只有这一台」。
    public func setDeviceConnected(_ target: MultiConnectDevice, connected: Bool) {
        guard !devices.isEmpty else {
            onLog?("设备列表为空，无法下发")
            return
        }

        let entries: [(mac: [UInt8], state: UInt8)] = devices.map { d in
            if d.macAddress == target.macAddress {
                return (
                    mac: d.macBytes,
                    state: (connected ? MultiConnectState.connect : .disconnect).rawValue
                )
            }
            // 其余设备**原样回传自己的状态字节**，而不是统一写 keep(=1)：
            // 0x02（当前活动设备）若被写成 1 会被降级为「已连接但非活动」
            return (mac: d.macBytes, state: d.stateByte)
        }

        // MAC 解析失败会让整张表错位，宁可不发
        guard entries.allSatisfy({ $0.mac.count == 6 }) else {
            onLog?("MAC 解析失败，已取消下发")
            return
        }

        send(
            try? builder.setMultiConnectDevices(entries),
            "\(connected ? "连接" : "断开")设备「\(target.name)」"
        )
        // 耳机不一定主动回报新列表，稍后主动回读
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            send(try? builder.queryMultiConnectDevices(), "回读设备列表")
        }
    }

    /// 调试台：发送任意原始 content 字节。
    public func sendRaw(_ bytes: [UInt8]) {
        send(bytes, "手动帧")
    }

    /// 依据设备名重新挑选 wire profile（连接后名字才确定）。
    public func adoptProfile(forDeviceName name: String?) {
        deviceName = name
        let profile = VivoModelCatalog.selectProfile(name)
        builder = VivoCommandBuilder(format: transport.format, profile: profile)
        onLog?("选定 profile：\(profile.label)")
    }

    private func send(_ bytes: [UInt8]?, _ label: String) {
        guard let bytes else {
            onLog?("\(label)：编码失败")
            return
        }
        onLog?("▶ \(label)")
        transport.send(bytes)
    }

    // MARK: - 帧分发

    private func wire() {
        transport.onLog = { [weak self] msg in
            self?.onLog?(msg)
        }

        transport.onStateChange = { [weak self] state in
            guard let self else { return }
            if case .ready(let name) = state {
                adoptProfile(forDeviceName: name)
            }
            onStateChange?(state)
        }

        transport.onFrame = { [weak self] frame in
            self?.handle(frame)
        }
    }

    private func handle(_ frame: GaiaFrame) {
        // 1) 耳机主动索要手机时间 —— 官方 App 会答，我们照做
        if frame.command == VivoGaia.Command.requestPhoneTime {
            onFrame?(frame, "耳机索要手机时间")
            if autoReplyPeerRequests, let reply = try? builder.replyPhoneTime(Date()) {
                transport.send(reply)
                onLog?("▶ 应答手机时间")
            }
            return
        }

        // 2) 结构化状态
        if let hs = HandshakeState.parse(frame) {
            handshakeAccepted = hs.accepted
            onFrame?(frame, "握手响应：\(hs.accepted ? "接受" : "拒绝")")
            onHandshake?(hs.accepted)
            return
        }
        if let b = BatteryState.parse(frame) {
            battery = b
            onFrame?(frame, "电量上报")
            onBattery?(b)
            return
        }
        if let n = NoiseState.parse(frame) {
            noise = n
            onFrame?(frame, "降噪\(n.acknowledged ? "设置确认" : "状态上报")：\(n.mode.displayName)")
            onNoise?(n)
            return
        }
        if let list = MultiConnectDevices.parse(frame) {
            devices = list
            onFrame?(frame, "多连接设备列表（\(list.count) 台）")
            onDevices?(list)
            return
        }

        // 3) 埋点上报：吸收，但把 eventId 摘出来便于调试
        if frame.command == VivoGaia.Command.reportTracking {
            let text = String(bytes: frame.payload.filter { $0 >= 0x20 && $0 < 0x7F },
                              encoding: .ascii) ?? ""
            let eventId = text.range(of: "\"eventId\":\"").map { r in
                String(text[r.upperBound...].prefix(while: { $0 != "\"" }))
            }
            onFrame?(frame, "耳机埋点上报\(eventId.map { " \($0)" } ?? "")")
            return
        }

        // 4) 未知帧：保留原样，这是继续逆向的线索
        onFrame?(frame, "未知命令")
    }
}

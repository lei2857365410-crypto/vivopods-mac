import SwiftUI
import VivoPodsKit

/// 调试台：原始帧收发记录 + 手动发帧。
///
/// 刻意保留这个面板——协议是逆向来的，未知命令需要能现场试（例如多连接控制的
/// 命令号就还没确认）。日常使用只用菜单栏即可，不必打开这里。
struct DebugConsoleView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader
            Divider()
            sendRow
            logList
            hint
        }
        .padding(12)
        .frame(minWidth: 460, minHeight: 400)
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.state.isReady ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.deviceTitle)
                    .font(.system(size: 12, weight: .semibold))
                Text(model.state.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let b = model.battery {
                Text(batterySummary(b))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Button("刷新") { model.refresh() }
                .disabled(!model.state.isReady)
        }
    }

    private func batterySummary(_ b: BatteryState) -> String {
        var parts: [String] = []
        if let l = b.left { parts.append("L\(l)%" + (b.leftCharging ? "⚡" : "")) }
        if let r = b.right { parts.append("R\(r)%" + (b.rightCharging ? "⚡" : "")) }
        if let c = b.caseLevel { parts.append("盒\(c)%" + (b.caseCharging ? "⚡" : "")) }
        return parts.joined(separator: "  ")
    }

    private var sendRow: some View {
        RawSendField { hex in model.sendRaw(hex: hex) }
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(model.logLines) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Text(line.time)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.tertiary)

                            Text(line.outgoing ? "▶" : "◀")
                                .font(.system(size: 9.5))
                                .foregroundStyle(line.outgoing ? Color.accentColor : .secondary)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(line.text)
                                    .font(.system(size: 10.5))
                                    .textSelection(.enabled)
                                if let hex = line.hex, !hex.isEmpty {
                                    Text(hex)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .id(line.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }
            .background(Color.secondary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onChange(of: model.logLines.count) {
                if let last = model.logLines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var hint: some View {
        Text("格式为裸 content：vendor(2) + command(2) + payload。"
             + "例如 001B0207 查电量、001B023000 查降噪。")
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
    }
}

struct RawSendField: View {
    @State private var text = ""
    let onSend: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField("原始 content，如 001B0207", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .onSubmit(send)

            Button("发送", action: send)
                .disabled(text.isEmpty)
        }
    }

    private func send() {
        guard !text.isEmpty else { return }
        onSend(text)
        text = ""
    }
}

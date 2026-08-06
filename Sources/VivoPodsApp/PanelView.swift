import SwiftUI
import VivoPodsKit

/// 状态栏下拉面板。
///
/// 用 `NSPopover` + SwiftUI 而不是 `NSMenu`：菜单项在 `isEnabled = false` 时，
/// 系统会把 `attributedTitle` 里显式指定的颜色一并变灰，标题与电量行怎么设都是灰的。
/// 面板里的文字颜色完全由我们控制，同时仍保持「点一下就切换」的交互。
struct PanelView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 10)
            noiseSection
            if !model.devices.isEmpty {
                Divider().padding(.vertical, 10)
                devicesSection
            }
            Divider().padding(.vertical, 10)
            footer
        }
        .padding(14)
        // fixedSize 锁定纵向为内容高度，避免内部的 Spacer 把面板顶到屏幕外
        .frame(width: 268)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 头部：设备名 + 左右电量

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.shortDeviceName)
                .font(.system(size: 14, weight: .semibold))
                // .primary 跟随系统外观：浅色下黑字、深色下白字
                .foregroundStyle(.primary)

            // 显示每个部件最后一次的有效读数。耳机不在盒中时 case 上报 0xFF、
            // 断开时完全没有新数据 —— 这些情况下仍显示旧值，但置灰表示非实时。
            if !model.batteryCache.isEmpty {
                HStack(spacing: 14) {
                    if let l = model.batteryCache.left {
                        BatteryPill(label: "左", reading: l)
                    }
                    if let r = model.batteryCache.right {
                        BatteryPill(label: "右", reading: r)
                    }
                    if let c = model.batteryCache.charging {
                        BatteryPill(label: "仓", reading: c)
                    }
                }
            } else {
                Text(model.state.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 降噪

    private var noiseSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("降噪模式")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(NoiseMode.allCases) { mode in
                    NoiseButton(
                        mode: mode,
                        selected: model.effectiveNoiseMode == mode,
                        pending: model.pendingNoiseMode == mode
                    ) {
                        model.setNoise(mode)
                    }
                }
            }
            .disabled(!model.state.isReady)
        }
    }

    // MARK: - 多连接设备

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("多连接设备")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            ForEach(model.devices) { d in
                DeviceRow(
                    device: d,
                    isSelf: model.isSelf(d),
                    enabled: model.canControlDevices
                ) {
                    model.toggleDevice(d)
                }
            }
        }
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            PanelButton(title: "刷新", symbol: "arrow.clockwise") {
                model.refresh()
            }
            .disabled(!model.state.isReady)

            PanelButton(
                title: "开机时启动",
                symbol: model.launchAtLogin ? "checkmark.square" : "square",
                subtitle: model.launchAtLoginNeedsApproval ? "需在系统设置中批准" : nil
            ) {
                model.toggleLaunchAtLogin()
            }

            PanelButton(title: "调试台", symbol: "terminal") {
                model.openDebugConsole?()
            }

            PanelButton(title: "退出 VivoPods", symbol: "power") {
                model.quit()
            }
        }
    }
}

// MARK: - 子视图

/// 单个部件的电量：`左 83%`，充电中加闪电。
///
/// `reading.isStale` 为 true 时数字置灰 —— 那是缓存下来的旧值，不是当前状态。
struct BatteryPill: View {
    let label: String
    let reading: BatteryReading

    private var tint: Color {
        // 缓存值统一用次要色，不参与低电量变红／充电变绿，
        // 否则会把过期数据渲染得像实时警示
        if reading.isStale { return .secondary }
        if reading.charging { return .green }
        return reading.level < 20 ? .red : .primary
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("\(reading.level)%")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(tint)
            if reading.charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.green)
            }
        }
        .help(reading.isStale ? "\(label)：上次读到的数值，非当前状态" : "")
    }
}

struct NoiseButton: View {
    let mode: NoiseMode
    let selected: Bool
    let pending: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 14))
                Text(mode.displayName)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(background)
            )
            .foregroundStyle(selected ? Color.white : Color.primary)
            .overlay(alignment: .topTrailing) {
                if pending {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(2)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if selected { return .accentColor }
        return hovering ? Color.secondary.opacity(0.2) : Color.secondary.opacity(0.11)
    }
}

struct DeviceRow: View {
    let device: MultiConnectDevice
    let isSelf: Bool
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(device.isActive ? Color.green
                          : (device.isConnected ? Color.orange : Color.secondary.opacity(0.35)))
                    .frame(width: 6, height: 6)

                Text(isSelf ? "\(device.name)（本机）" : device.name)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(device.stateLabel)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hovering && canTap ? Color.secondary.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        // 本机自己不能断开——断了就再也发不出命令
        .disabled(!canTap)
        .onHover { hovering = $0 }
        .help(isSelf ? "当前主机，不能断开" : device.macAddress)
    }

    private var canTap: Bool { enabled && !isSelf }
}

/// 面板底部的行式按钮，悬停高亮。
struct PanelButton: View {
    let title: String
    let symbol: String
    var subtitle: String? = nil
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 12))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hovering && isEnabled ? Color.secondary.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

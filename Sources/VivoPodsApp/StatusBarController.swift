import AppKit
import Combine
import SwiftUI
import VivoPodsKit

/// 菜单栏控制器：状态栏图标 + 点击弹出的下拉面板。
///
/// 面板用 `NSPopover` 承载 SwiftUI，而不是 `NSMenu`：
/// 菜单项在 `isEnabled = false` 时，系统会把 `attributedTitle` 里显式指定的颜色
/// 一并做变灰处理，标题与电量行怎么设都是灰的。改成面板后文字颜色完全可控，
/// 同时保留了「点一下就切降噪 / 选设备」的交互。
@MainActor
final class StatusBarController: NSObject {

    private let model: AppModel
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var debugWindow: NSWindow?
    /// 面板打开期间监听外部点击，点面板外就关掉。
    private var clickMonitor: Any?

    init(model: AppModel) {
        self.model = model
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        popover.behavior = .transient
        popover.animates = false
        let hosting = NSHostingController(
            rootView: PanelView().environmentObject(model)
        )
        // 必须显式声明按内容自适应尺寸：默认行为下 NSHostingController 会把
        // SwiftUI 视图拉伸到一个不受约束的高度，面板会超出屏幕，只剩顶部可见。
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        model.openDebugConsole = { [weak self] in
            self?.openDebug()
        }

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // objectWillChange 在赋值前触发，下一个 tick 再读才是新值
                DispatchQueue.main.async { self?.updateTitle() }
            }
            .store(in: &cancellables)

        updateTitle()
    }

    // MARK: - 菜单栏标题

    private func updateTitle() {
        guard let button = statusItem.button else { return }

        // 耳机没连上时隐藏图标（App 仍在后台等待，连上后自动出现）。
        // 但蓝牙关闭 / 未授权这类需要用户干预的情况必须显示，否则用户既看不到
        // 问题所在，也没有任何入口能退出 App 或关掉开机自启。
        let needsAttention: Bool
        switch model.state {
        case .bluetoothOff, .unauthorized, .unsupported:
            needsAttention = true
        default:
            needsAttention = false
        }
        statusItem.isVisible = model.state.isReady || needsAttention
        guard statusItem.isVisible else {
            if popover.isShown { closePanel() }
            return
        }

        if needsAttention {
            button.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "蓝牙不可用"
            )
            button.image?.isTemplate = true
            button.attributedTitle = NSAttributedString(string: "")
            return
        }

        button.image = NSImage(
            systemSymbolName: model.statusSymbol,
            accessibilityDescription: "vivo 耳机"
        )
        button.image?.isTemplate = true

        let color: NSColor = model.statusIsLow ? .systemRed : .labelColor
        button.attributedTitle = NSAttributedString(
            string: " " + model.statusText,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: color,
            ]
        )
    }

    // MARK: - 面板开关

    @objc private func togglePanel() {
        popover.isShown ? closePanel() : openPanel()
    }

    private func openPanel() {
        guard let button = statusItem.button else { return }

        // 打开时刷新一次，保证看到的是最新电量
        if model.state.isReady {
            model.refresh()
        }
        // 自启状态可能被用户在系统设置里改过，每次打开都重新读
        model.launchAtLogin = LoginItem.isEnabled
        model.launchAtLoginNeedsApproval = LoginItem.requiresApproval

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // 兜底关闭：.transient 在点击其它 App 的菜单栏项时不一定会自动收起。
        //
        // 用 global monitor（只收本 App 之外的点击），所以面板内按钮不受影响；
        // 但状态栏按钮自身的点击也会到这里，若直接关闭会与 togglePanel 打架
        // （一次点击先被这里关掉、再被 toggle 打开），因此显式排除状态栏所在区域。
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                // 全局监听拿到的事件没有关联窗口，locationInWindow 即屏幕坐标
                let screenPoint = event.locationInWindow
                if let buttonFrame = self.statusItem.button?.window?.frame,
                   buttonFrame.contains(screenPoint) {
                    return  // 点在状态栏图标上，交给 togglePanel 处理
                }
                self.closePanel()
            }
        }
    }

    private func closePanel() {
        popover.performClose(nil)
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    // MARK: - 调试台

    private func openDebug() {
        closePanel()

        if let win = debugWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = DebugConsoleView().environmentObject(model)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "VivoPods 调试台"
        win.contentView = NSHostingView(rootView: view)
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        debugWindow = win
    }
}

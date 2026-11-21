import AppKit
import SwiftUI
import VivoPodsKit

/// 纯 AppKit 入口。
///
/// 不用 SwiftUI 的 `MenuBarExtra`：需求是点一下菜单栏就能直接切降噪 / 选设备，
/// 原生 `NSMenu` 的勾选项与单击即执行最贴合这个交互，也不必先展开一个面板。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement 已在 Info.plist 里置为 true，这里再兜一层，
        // 保证从终端直接运行可执行文件时也不会出现 Dock 图标
        NSApp.setActivationPolicy(.accessory)

        model = AppModel()
        statusBar = StatusBarController(model: model)

        if ProcessInfo.processInfo.environment["VIVOPODS_VERBOSE"] == "1" {
            print("登录项状态：enabled=\(LoginItem.isEnabled) "
                  + "requiresApproval=\(LoginItem.requiresApproval)")
            fflush(stdout)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()

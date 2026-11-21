import Foundation
import ServiceManagement

/// 开机自启开关。
///
/// 用 `SMAppService.mainApp`（macOS 13+）。它把 App 注册进「登录项」，
/// 用户也能在 系统设置 ▸ 通用 ▸ 登录项与扩展 里看到并手动关闭。
///
/// - Note: 该 API 要求 App 已签名。本项目用 ad-hoc 签名（`codesign -s -`），
///   实测可用；但 App 被移动位置后注册会失效，需要重新开一次。
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 当前状态是否为「用户在系统设置里手动禁用了」。
    ///
    /// 这种情况下 `register()` 不会生效，必须引导用户去系统设置里开。
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// 返回是否成功；失败时给出可展示的原因。
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> (ok: Bool, message: String?) {
        do {
            if enabled {
                // 已注册时再次 register 会抛错，先判断
                guard SMAppService.mainApp.status != .enabled else {
                    return (true, nil)
                }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else {
                    return (true, nil)
                }
                try SMAppService.mainApp.unregister()
            }
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// 打开系统设置的登录项面板，供用户手动批准。
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

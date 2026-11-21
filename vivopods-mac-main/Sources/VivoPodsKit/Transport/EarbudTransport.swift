import Foundation

/// 传输层连接状态。
public enum TransportState: Sendable, Equatable {
    case idle
    case bluetoothOff
    case unauthorized
    case unsupported
    /// 正在查找设备（retrieveConnected / 扫描）
    case searching
    case connecting(String)
    /// 已建立控制通道，可收发帧
    case ready(String)
    case disconnected(String?)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var label: String {
        switch self {
        case .idle: return "未开始"
        case .bluetoothOff: return "蓝牙已关闭"
        case .unauthorized: return "蓝牙未授权"
        case .unsupported: return "设备不支持"
        case .searching: return "查找设备中…"
        case .connecting(let n): return "连接中：\(n)"
        case .ready(let n): return "已连接：\(n)"
        case .disconnected(let e): return e.map { "已断开：\($0)" } ?? "已断开"
        }
    }
}

/// 耳机控制通道抽象。
///
/// 两个实现（BLE GATT / RFCOMM SPP）对上层完全等价，差异只在 `format` 与内部实现，
/// 因此会话层与 UI 不需要感知走的是哪条通道。
public protocol EarbudTransport: AnyObject {
    /// 该通道使用的帧封装。
    var format: WireFormat { get }
    var state: TransportState { get }

    /// 收到一帧（已按 `format` 解码）。
    var onFrame: ((GaiaFrame) -> Void)? { get set }
    /// 收到原始字节（调试台用，未解码）。
    var onRawIn: (([UInt8]) -> Void)? { get set }
    /// 发出原始字节（调试台用）。
    var onRawOut: (([UInt8]) -> Void)? { get set }
    /// 人类可读的过程日志。
    var onLog: ((String) -> Void)? { get set }
    var onStateChange: ((TransportState) -> Void)? { get set }

    func start()
    func send(_ bytes: [UInt8])
    func stop()
}

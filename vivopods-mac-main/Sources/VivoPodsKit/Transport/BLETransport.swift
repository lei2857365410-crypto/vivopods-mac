import Foundation
import CoreBluetooth

/// BLE GATT 控制通道。
///
/// 走的是 vivo iOS 版 App 实测使用的那条路径：
/// 服务 `00001100-D102-11E1-9B23-00025B00A5A5`，写特征 `…1101`，通知特征 `…1102`。
///
/// 设备发现优先用 `retrieveConnectedPeripherals(withServices:)` —— 官方 App 就是这样拿到
/// 耳机的（其日志中 `filterRetrieveDevices-etrieveConnectedPeripherals:1`）。耳机以经典蓝牙
/// 连着 Mac 时并不一定在 LE 上广播该服务，所以扫描兜底**不加服务过滤**，改用名称前缀 +
/// vivo FastPair 广播特征来筛。
public final class BLETransport: NSObject, EarbudTransport {

    public let format: WireFormat = .gatt

    public private(set) var state: TransportState = .idle {
        didSet { onStateChange?(state) }
    }

    public var onFrame: ((GaiaFrame) -> Void)?
    public var onRawIn: (([UInt8]) -> Void)?
    public var onRawOut: (([UInt8]) -> Void)?
    public var onLog: ((String) -> Void)?
    public var onStateChange: ((TransportState) -> Void)?

    private let serviceUUID = CBUUID(string: VivoGaia.GATT.service)
    private let writeUUID = CBUUID(string: VivoGaia.GATT.writeCharacteristic)
    private let notifyUUID = CBUUID(string: VivoGaia.GATT.notifyCharacteristic)

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    /// 实测：`…1101` 的 properties = 0x04，即 **writeWithoutResponse**（0x08 才是带响应的
    /// write）。一开始按 `.withResponse` 发，CoreBluetooth 一律回
    /// "Writing is not permitted."。这里按特征实际支持的属性选类型。
    private var writeType: CBCharacteristicWriteType = .withoutResponse
    private let decoder = GaiaDecoder(format: .gatt)

    /// 只连名字匹配的设备；nil 表示接受任意 vivo/iQOO TWS。
    private let preferredName: String?
    private var didStart = false

    public init(preferredName: String? = nil) {
        self.preferredName = preferredName
        super.init()
    }

    public func start() {
        if didStart {
            // 重连路径：CBCentralManager 已存在，直接重新找设备即可。
            // 不能因为 didStart 就直接 return，否则断开后永远连不回来。
            if central?.state == .poweredOn {
                locateDevice()
            }
            return
        }
        didStart = true
        // queue: nil → 回调走主队列；CLI 侧由 RunLoop 驱动
        central = CBCentralManager(delegate: self, queue: nil)
    }

    public func send(_ bytes: [UInt8]) {
        guard let peripheral, let writeChar else {
            onLog?("发送失败：通道尚未就绪")
            return
        }
        onRawOut?(bytes)
        peripheral.writeValue(Data(bytes), for: writeChar, type: writeType)
    }

    public func stop() {
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        if central?.isScanning == true {
            central?.stopScan()
        }
        peripheral = nil
        writeChar = nil
        decoder.reset()
    }

    // MARK: - 设备发现

    private func locateDevice() {
        state = .searching

        // 1) 已连接外设（耳机以经典蓝牙连着 Mac 时走这条）
        let connected = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
        onLog?("retrieveConnectedPeripherals(vivo 服务) → \(connected.count) 个")
        for p in connected {
            onLog?("   已连接外设：\(p.name ?? "(无名)")  \(p.identifier)")
        }
        if let target = pick(from: connected) {
            connect(to: target)
            return
        }

        // 2) 扫描兜底。不加服务过滤：耳机连着经典蓝牙时通常不在 LE 广播该服务
        onLog?("未从已连接外设找到，改为扫描（无服务过滤，按名称/FastPair 筛选）…")
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    private func pick(from list: [CBPeripheral]) -> CBPeripheral? {
        if let preferredName {
            return list.first { $0.name == preferredName } ?? list.first
        }
        return list.first { VivoModelCatalog.isFamilyName($0.name) } ?? list.first
    }

    private func connect(to target: CBPeripheral) {
        if central.isScanning { central.stopScan() }
        peripheral = target
        target.delegate = self
        state = .connecting(target.name ?? "(无名)")
        onLog?("发起连接：\(target.name ?? "(无名)")")
        central.connect(target, options: nil)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLETransport: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            onLog?("蓝牙就绪 (poweredOn)")
            locateDevice()
        case .poweredOff:
            state = .bluetoothOff
        case .unauthorized:
            state = .unauthorized
        case .unsupported:
            state = .unsupported
        default:
            onLog?("蓝牙状态：\(central.state.rawValue)")
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advName

        var matched = false
        if let preferredName {
            matched = (name == preferredName)
        } else if VivoModelCatalog.isFamilyName(name) {
            matched = true
        } else if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
                  VivoFastPairAdvertisement.parse([UInt8](mfg)) != nil {
            matched = true
        }
        guard matched else { return }

        onLog?("扫描命中：\(name ?? "(无名)")  RSSI \(RSSI)")
        connect(to: peripheral)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        onLog?("已连接，开始发现服务…")
        peripheral.discoverServices([serviceUUID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        state = .disconnected(error?.localizedDescription ?? "连接失败")
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        writeChar = nil
        decoder.reset()
        state = .disconnected(error?.localizedDescription)
    }
}

// MARK: - CBPeripheralDelegate

extension BLETransport: CBPeripheralDelegate {

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        if let error {
            onLog?("发现服务失败：\(error.localizedDescription)")
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            onLog?("未找到 vivo 控制服务 \(serviceUUID)")
            state = .disconnected("缺少 vivo 控制服务")
            return
        }
        onLog?("找到服务 \(service.uuid)，发现特征…")
        peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: service)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            onLog?("发现特征失败：\(error.localizedDescription)")
            return
        }
        for ch in service.characteristics ?? [] {
            if ch.uuid == writeUUID {
                writeChar = ch
                // 按实际属性挑写入类型：优先带响应，否则无响应
                if ch.properties.contains(.write) {
                    writeType = .withResponse
                } else if ch.properties.contains(.writeWithoutResponse) {
                    writeType = .withoutResponse
                } else {
                    onLog?("⚠️ 写特征既不支持 write 也不支持 writeWithoutResponse")
                }
                onLog?("写特征就绪 \(ch.uuid) properties=0x\(String(ch.properties.rawValue, radix: 16))"
                       + " → \(writeType == .withResponse ? "withResponse" : "withoutResponse")")
            } else if ch.uuid == notifyUUID {
                onLog?("订阅通知特征 \(ch.uuid) properties=0x\(String(ch.properties.rawValue, radix: 16))")
                peripheral.setNotifyValue(true, for: ch)
            }
        }
        if writeChar == nil {
            state = .disconnected("缺少写特征")
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == notifyUUID else { return }
        if let error {
            onLog?("订阅失败：\(error.localizedDescription)")
            return
        }
        if characteristic.isNotifying, writeChar != nil {
            onLog?("通道就绪，可收发")
            state = .ready(peripheral.name ?? "(无名)")
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value, !data.isEmpty else { return }
        let bytes = [UInt8](data)
        onRawIn?(bytes)
        for frame in decoder.offer(bytes) {
            onFrame?(frame)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            onLog?("写入失败：\(error.localizedDescription)")
        }
    }
}

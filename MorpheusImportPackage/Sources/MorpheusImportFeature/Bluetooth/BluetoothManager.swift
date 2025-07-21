import Foundation
import CoreBluetooth
import os.log

@Observable
@MainActor
final class BluetoothManager: NSObject {
    nonisolated let logger = Logger(subsystem: "com.morpheusimport.app", category: "BluetoothManager")
    
    // MARK: - State
    var isScanning = false
    var discoveredDevices: [DiscoveredDevice] = []
    var connectedDevice: DiscoveredDevice?
    var bluetoothState: CBManagerState = .unknown
    var lastHeartRate: Int?
    var dataLogs: [DataLog] = []
    var currentSessionID: String?
    
    // MARK: - File Management & Parsing
    private let fileManager = DataFileManager()
    private let morpheusParser = MorpheusDataParser()
    
    // MARK: - Core Bluetooth
    private var centralManager: CBCentralManager!
    private(set) var connectedPeripheral: CBPeripheral?
    
    // MARK: - Standard BLE Heart Rate Service UUIDs
    private let heartRateServiceUUID = CBUUID(string: "0x180D")
    private let heartRateMeasurementCharacteristicUUID = CBUUID(string: "0x2A37")
    private let bodySensorLocationCharacteristicUUID = CBUUID(string: "0x2A38")
    
    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public Methods
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            logger.warning("Bluetooth not powered on")
            return
        }
        
        isScanning = true
        discoveredDevices.removeAll()
        
        // Scan for devices advertising heart rate service
        centralManager.scanForPeripherals(
            withServices: [heartRateServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        logger.info("Started scanning for heart rate monitors")
    }
    
    func stopScanning() {
        isScanning = false
        centralManager.stopScan()
        logger.info("Stopped scanning")
    }
    
    func connect(to device: DiscoveredDevice) {
        stopScanning()
        centralManager.connect(device.peripheral, options: nil)
        logger.info("Attempting to connect to \(device.name)")
    }
    
    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    // MARK: - Session Management
    func startNewSession(deviceName: String) {
        self.currentSessionID = fileManager.createNewSession(deviceName: deviceName)
        logger.info("Started new data collection session: \(self.currentSessionID ?? "unknown")")
    }
    
    func stopCurrentSession() {
        if let sessionID = self.currentSessionID {
            Task {
                await fileManager.logAnalysis("Session ended", sessionID: sessionID)
            }
            logger.info("Stopped data collection session: \(sessionID)")
        }
        self.currentSessionID = nil
    }
    
    // MARK: - Data Logging for Reverse Engineering
    
    func exportLogs() -> String {
        let header = "Timestamp,Characteristic UUID,Hex Data,ASCII\n"
        let rows = dataLogs.map { log in
            let ascii = String(data: log.data, encoding: .ascii) ?? "N/A"
            return "\(log.timestamp.ISO8601Format()),\(log.characteristicUUID),\(log.hexString),\(ascii)"
        }
        return header + rows.joined(separator: "\n")
    }
    
    // MARK: - File Management Access
    func getAllSessions() -> [String] {
        return fileManager.getAllSessions()
    }
    
    func exportSessionFiles(_ sessionID: String) -> [URL] {
        return fileManager.exportSessionData(sessionID)
    }
    
    func deleteSession(_ sessionID: String) async {
        await fileManager.deleteSession(sessionID)
    }
    
    func getDataDirectoryURL() -> URL {
        return fileManager.getDataDirectoryURL()
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.bluetoothState = state
            
            switch state {
            case .poweredOn:
                self.logger.info("Bluetooth powered on")
            case .poweredOff:
                self.logger.warning("Bluetooth powered off")
                self.stopScanning()
            case .unauthorized:
                self.logger.error("Bluetooth unauthorized")
            case .unsupported:
                self.logger.error("Bluetooth unsupported")
            default:
                break
            }
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Device"
        let isMorpheus = name.lowercased().contains("morpheus") || name.lowercased().contains("hrm")
        let rssiValue = RSSI.intValue
        let peripheralId = peripheral.identifier
        
        let device = DiscoveredDevice(
            peripheral: peripheral,
            name: name,
            rssi: rssiValue,
            advertisementData: advertisementData,
            isMorpheus: isMorpheus
        )
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Update or add device
            if let index = self.discoveredDevices.firstIndex(where: { $0.peripheral.identifier == peripheralId }) {
                self.discoveredDevices[index] = device
            } else {
                self.discoveredDevices.append(device)
            }
            
            self.logger.info("Discovered device: \(name) (RSSI: \(rssiValue))")
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let peripheralId = peripheral.identifier
        let peripheralName = peripheral.name ?? "device"
        
        // Set delegate immediately on the calling thread
        peripheral.delegate = self
        
        // Discover services on the Bluetooth queue
        peripheral.discoverServices(nil)
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Find the device by ID and update connection state
            if let device = self.discoveredDevices.first(where: { $0.peripheral.identifier == peripheralId }) {
                self.connectedDevice = device
                self.connectedPeripheral = device.peripheral // Use the peripheral from the device
                
                // Start a new data collection session
                self.startNewSession(deviceName: device.name)
                
                Task {
                    await self.fileManager.logAnalysis("Connected to device: \(device.name)", sessionID: self.currentSessionID!)
                }
            }
            
            self.logger.info("Connected to \(peripheralName)")
        }
    }
    
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Stop current session if active
            if let sessionID = self.currentSessionID {
                let disconnectReason = error?.localizedDescription ?? "Normal disconnect"
                Task {
                    await self.fileManager.logAnalysis("Disconnected: \(disconnectReason)", sessionID: sessionID)
                }
                self.stopCurrentSession()
            }
            
            self.connectedPeripheral = nil
            self.connectedDevice = nil
            self.lastHeartRate = nil
            
            if let error = error {
                self.logger.error("Disconnected with error: \(error.localizedDescription)")
            } else {
                self.logger.info("Disconnected from device")
            }
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.logger.error("Error discovering services: \(error!.localizedDescription)")
            }
            return
        }
        
        let servicesCount = peripheral.services?.count ?? 0
        let serviceUUIDs = peripheral.services?.map { $0.uuid.uuidString } ?? []
        
        // Discover characteristics on the Bluetooth queue
        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics(nil, for: service)
        }
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.logger.info("Discovered \(servicesCount) services")
            
            // Log all services for analysis
            for uuid in serviceUUIDs {
                self.logger.info("Service: \(uuid)")
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            let errorMessage = error!.localizedDescription
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.logger.error("Error discovering characteristics: \(errorMessage)")
            }
            return
        }
        
        let serviceUUID = service.uuid.uuidString
        let characteristicsCount = service.characteristics?.count ?? 0
        let characteristicInfo = service.characteristics?.map { characteristic in
            (uuid: characteristic.uuid.uuidString, properties: "\(characteristic.properties)")
        } ?? []
        
        // Process characteristics on the Bluetooth queue
        service.characteristics?.forEach { characteristic in
            // Read if possible
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
            
            // Subscribe to notifications if possible
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.logger.info("Service \(serviceUUID) has \(characteristicsCount) characteristics")
            
            // Log all characteristics for analysis
            for info in characteristicInfo {
                self.logger.info("  Characteristic: \(info.uuid) - Properties: \(info.properties)")
            }
        }
    }
    
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        
        let characteristicUUIDString = characteristic.uuid.uuidString
        let timestamp = Date()
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Create log entry directly (avoiding passing characteristic object)
            let log = DataLog(
                timestamp: timestamp,
                characteristicUUID: characteristicUUIDString,
                data: data,
                hexString: data.map { String(format: "%02hhX", $0) }.joined(separator: " ")
            )
            self.dataLogs.append(log)
            self.logger.debug("Logged data from \(characteristicUUIDString): \(log.hexString)")
            
            // Save to file if we have an active session
            if let sessionID = self.currentSessionID {
                Task {
                    await self.fileManager.logRawData(
                        data, 
                        characteristicUUID: characteristicUUIDString, 
                        sessionID: sessionID, 
                        timestamp: timestamp
                    )
                    
                    await self.fileManager.logBinaryData(
                        data,
                        characteristicUUID: characteristicUUIDString,
                        sessionID: sessionID,
                        timestamp: timestamp
                    )
                }
            }
            
            // Parse data using Morpheus parser
            if let parsedData = self.morpheusParser.parseCharacteristicData(data, characteristicUUID: characteristicUUIDString) {
                // Update heart rate if parsed
                if let heartRate = parsedData.heartRate {
                    self.lastHeartRate = heartRate
                    self.logger.info("Updated heart rate: \(heartRate) bpm from \(characteristicUUIDString)")
                    
                    // Log heart rate to file
                    if let sessionID = self.currentSessionID {
                        Task {
                            await self.fileManager.logHeartRate(heartRate, sessionID: sessionID)
                        }
                    }
                }
                
                // Log analysis report for Morpheus data
                if let sessionID = self.currentSessionID {
                    let analysisReport = self.morpheusParser.generateAnalysisReport(for: parsedData)
                    Task {
                        await self.fileManager.logAnalysis(analysisReport, sessionID: sessionID)
                    }
                }
            }
        }
    }
    
}

// MARK: - Supporting Types
struct DiscoveredDevice: Identifiable, @unchecked Sendable {
    let id = UUID()
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
    let advertisementData: [String: Any]
    let isMorpheus: Bool
}

struct DataLog: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let characteristicUUID: String
    let data: Data
    let hexString: String
}
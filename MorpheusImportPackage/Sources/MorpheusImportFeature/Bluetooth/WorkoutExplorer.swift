import Foundation
import CoreBluetooth
import os.log

/// Tool for reverse engineering Morpheus workout download protocol
@MainActor
final class WorkoutExplorer: ObservableObject {
    nonisolated let logger = Logger(subsystem: "com.morpheusimport.app", category: "WorkoutExplorer")
    
    // MARK: - State
    @Published var isExploring = false
    @Published var explorationLog: [String] = []
    @Published var discoveredCommands: [WorkoutCommand] = []
    
    // MARK: - BLE References
    private weak var peripheral: CBPeripheral?
    private let fileManager = DataFileManager()
    
    // MARK: - Known Characteristics (from your log)
    private let knownCharacteristics = [
        // FC00 Service - Likely workout management
        "FC20": CharacteristicInfo(uuid: "FC20", service: "FC00", properties: .notify, purpose: "Real-time data stream"),
        "FC21": CharacteristicInfo(uuid: "FC21", service: "FC00", properties: .write, purpose: "Command interface (suspected)"),
        
        // FD00 Service - Likely workout data transfer
        "FD09": CharacteristicInfo(uuid: "FD09", service: "FD00", properties: .notify, purpose: "Data transfer channel 1"),
        "FD0A": CharacteristicInfo(uuid: "FD0A", service: "FD00", properties: .write, purpose: "Control channel 1"),
        "FD15": CharacteristicInfo(uuid: "FD15", service: "FD00", properties: .notify, purpose: "Data transfer channel 2"), 
        "FD16": CharacteristicInfo(uuid: "FD16", service: "FD00", properties: .write, purpose: "Control channel 2")
    ]
    
    // MARK: - Exploration Commands
    private let explorationCommands: [WorkoutCommand] = [
        // Common workout enumeration commands
        WorkoutCommand(name: "List Workouts", data: Data([0x01]), description: "Request workout list"),
        WorkoutCommand(name: "Workout Count", data: Data([0x02]), description: "Get number of stored workouts"),
        WorkoutCommand(name: "Status Query", data: Data([0x00]), description: "General status request"),
        WorkoutCommand(name: "Device Info", data: Data([0x03]), description: "Extended device information"),
        
        // Download-related commands
        WorkoutCommand(name: "Download Start", data: Data([0x10, 0x00]), description: "Start download session"),
        WorkoutCommand(name: "Download Workout 1", data: Data([0x11, 0x01]), description: "Download first workout"),
        WorkoutCommand(name: "Download Workout 2", data: Data([0x11, 0x02]), description: "Download second workout"),
        WorkoutCommand(name: "Download End", data: Data([0x12]), description: "End download session"),
        
        // Sync and memory commands
        WorkoutCommand(name: "Sync Request", data: Data([0x20]), description: "Sync workout data"),
        WorkoutCommand(name: "Memory Status", data: Data([0x21]), description: "Check memory usage"),
        WorkoutCommand(name: "Clear Memory", data: Data([0x22]), description: "Clear workout memory"),
        
        // Protocol discovery
        WorkoutCommand(name: "Protocol Version", data: Data([0xF0]), description: "Get protocol version"),
        WorkoutCommand(name: "Capabilities", data: Data([0xF1]), description: "Get device capabilities"),
        
        // Common BLE patterns
        WorkoutCommand(name: "Handshake", data: Data([0xFF, 0x00]), description: "Initiate communication"),
        WorkoutCommand(name: "Keep Alive", data: Data([0xFE]), description: "Keep connection alive"),
        
        // Data format queries
        WorkoutCommand(name: "Data Format", data: Data([0x30]), description: "Query data format"),
        WorkoutCommand(name: "Time Sync", data: Data([0x31, 0x00, 0x00, 0x00, 0x00]), description: "Sync device time"),
        
        // Morpheus-specific guesses (based on observed patterns)
        WorkoutCommand(name: "Morpheus List", data: Data([0x0A, 0x01]), description: "List workouts (Morpheus style)"),
        WorkoutCommand(name: "Morpheus Download", data: Data([0x0A, 0x02, 0x01]), description: "Download workout (Morpheus style)"),
        WorkoutCommand(name: "Morpheus Status", data: Data([0x0A, 0x00]), description: "Get status (Morpheus style)")
    ]
    
    // MARK: - Public Methods
    
    func startExploration(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        self.isExploring = true
        self.explorationLog.removeAll()
        
        addLog("🔍 Starting workout protocol exploration for \(peripheral.name ?? "Unknown")")
        addLog("📋 Will test \(explorationCommands.count) commands across \(knownCharacteristics.count) characteristics")
        
        // Start systematic exploration
        Task {
            await exploreWorkoutProtocol()
        }
    }
    
    func stopExploration() {
        isExploring = false
        addLog("⏹️ Exploration stopped by user")
    }
    
    // MARK: - Private Exploration Methods
    
    private func exploreWorkoutProtocol() async {
        guard let peripheral = peripheral else { return }
        
        addLog("🚀 Beginning systematic exploration...")
        
        // Phase 1: Subscribe to all notification characteristics
        await subscribeToNotifications(peripheral)
        
        // Phase 2: Test commands on write characteristics
        await testCommands(peripheral)
        
        // Phase 3: Analyze responses and generate report
        await generateExplorationReport()
        
        isExploring = false
        addLog("✅ Exploration complete!")
    }
    
    private func subscribeToNotifications(_ peripheral: CBPeripheral) async {
        addLog("📡 Phase 1: Subscribing to notification characteristics...")
        
        guard let services = peripheral.services else {
            addLog("❌ No services found")
            return
        }
        
        for service in services {
            guard let characteristics = service.characteristics else { continue }
            
            for characteristic in characteristics {
                let uuid = characteristic.uuid.uuidString.uppercased()
                
                if characteristic.properties.contains(.notify) {
                    addLog("🔔 Subscribing to notifications: \(uuid)")
                    peripheral.setNotifyValue(true, for: characteristic)
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                }
            }
        }
        
        addLog("✅ Phase 1 complete - All notification characteristics subscribed")
    }
    
    private func testCommands(_ peripheral: CBPeripheral) async {
        addLog("🧪 Phase 2: Testing workout commands...")
        
        guard let services = peripheral.services else { return }
        
        // Find write characteristics
        let writeCharacteristics = services.flatMap { service in
            service.characteristics?.filter { $0.properties.contains(.write) } ?? []
        }
        
        addLog("✍️ Found \(writeCharacteristics.count) write characteristics")
        
        for characteristic in writeCharacteristics {
            let uuid = characteristic.uuid.uuidString.uppercased()
            addLog("📝 Testing commands on characteristic: \(uuid)")
            
            for command in explorationCommands {
                addLog("   → Sending: \(command.name) (\(command.data.map { String(format: "%02X", $0) }.joined(separator: " ")))")
                
                // Send command
                peripheral.writeValue(command.data, for: characteristic, type: .withResponse)
                
                // Wait for potential response
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                
                // Log any responses we might have received
                // (responses will be captured by the main BluetoothManager)
            }
            
            addLog("✅ Completed testing on \(uuid)")
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second break between characteristics
        }
        
        addLog("✅ Phase 2 complete - All commands tested")
    }
    
    private func generateExplorationReport() async {
        addLog("📊 Phase 3: Generating exploration report...")
        
        let reportFormatter = DateFormatter()
        reportFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        reportFormatter.timeZone = TimeZone(abbreviation: "UTC")
        let reportTimestamp = reportFormatter.string(from: Date())
        
        let report = """
        
        =====================================
        MORPHEUS WORKOUT EXPLORATION REPORT
        =====================================
        Device: \(peripheral?.name ?? "Unknown")
        Timestamp: \(reportTimestamp)
        
        TESTED CHARACTERISTICS:
        \(knownCharacteristics.map { "- \($0.key): \($0.value.purpose)" }.joined(separator: "\n"))
        
        TESTED COMMANDS:
        \(explorationCommands.enumerated().map { "\($0.offset + 1). \($0.element.name): \($0.element.data.map { String(format: "%02X", $0) }.joined(separator: " "))" }.joined(separator: "\n"))
        
        ANALYSIS NOTES:
        - Monitor the main app logs for any responses to these commands
        - Look for changes in FC20 real-time data stream
        - Check for new data on FD09/FD15 notification characteristics
        - Any successful commands should trigger data responses
        
        NEXT STEPS:
        1. Review captured data for response patterns
        2. Identify which commands produced responses
        3. Refine command parameters based on findings
        4. Build workout download protocol implementation
        
        =====================================
        """
        
        addLog(report)
        
        // Save report to file
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        let timestamp = formatter.string(from: Date())
        let sessionID = "WorkoutExploration_\(timestamp)"
        await fileManager.logAnalysis(report, sessionID: sessionID)
        
        addLog("💾 Report saved to session: \(sessionID)")
    }
    
    // MARK: - Helper Methods
    
    private func addLog(_ message: String) {
        let timestampedMessage = "[\(Date().formatted(date: .omitted, time: .standard))] \(message)"
        explorationLog.append(timestampedMessage)
        logger.info("\(message)")
    }
    
    func getLogText() -> String {
        return explorationLog.joined(separator: "\n")
    }
}

// MARK: - Supporting Types

struct CharacteristicInfo {
    let uuid: String
    let service: String
    let properties: CBCharacteristicProperties
    let purpose: String
}

struct WorkoutCommand: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
    let description: String
    
    var hexString: String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

// MARK: - CBCharacteristicProperties Extension

extension CBCharacteristicProperties {
    static let notify = CBCharacteristicProperties(rawValue: 16)
    static let write = CBCharacteristicProperties(rawValue: 4)
}
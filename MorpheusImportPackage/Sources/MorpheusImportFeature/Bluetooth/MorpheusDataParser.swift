import Foundation
import os.log

/// Parser for Morpheus M7-11954 heart rate monitor proprietary data format
@MainActor
final class MorpheusDataParser {
    nonisolated let logger = Logger(subsystem: "com.morpheusimport.app", category: "MorpheusDataParser")
    
    // MARK: - Parsed Data Structure
    struct MorpheusData: Sendable {
        let timestamp: Date
        let heartRate: Int?
        let rrInterval: Int?
        let batteryLevel: Int?
        let rawData: Data
        let characteristicUUID: String
        
        // Additional parsed fields from FC20 characteristic
        let packetCounter: UInt8?
        let statusFlag: UInt8?
        let deviceTimestamp: UInt32?
        let additionalSensorData: Data?
    }
    
    // MARK: - Standard BLE Parsing
    
    /// Parse standard heart rate measurement from characteristic 2A37
    func parseHeartRateMeasurement(_ data: Data) -> MorpheusData? {
        guard data.count >= 2 else { return nil }
        
        let bytes = [UInt8](data)
        let flags = bytes[0]
        
        // Check if heart rate format is 8-bit or 16-bit
        let isHeartRate16Bit = (flags & 0x01) != 0
        
        let heartRate: Int
        if isHeartRate16Bit && data.count >= 3 {
            heartRate = Int(bytes[1]) | (Int(bytes[2]) << 8)
        } else {
            heartRate = Int(bytes[1])
        }
        
        logger.info("Parsed standard heart rate: \(heartRate) bpm")
        
        return MorpheusData(
            timestamp: Date(),
            heartRate: heartRate,
            rrInterval: nil,
            batteryLevel: nil,
            rawData: data,
            characteristicUUID: "2A37",
            packetCounter: nil,
            statusFlag: nil,
            deviceTimestamp: nil,
            additionalSensorData: nil
        )
    }
    
    /// Parse battery level from characteristic 2A19
    func parseBatteryLevel(_ data: Data) -> MorpheusData? {
        guard data.count >= 1 else { return nil }
        
        let batteryLevel = Int(data[0])
        logger.info("Parsed battery level: \(batteryLevel)%")
        
        return MorpheusData(
            timestamp: Date(),
            heartRate: nil,
            rrInterval: nil,
            batteryLevel: batteryLevel,
            rawData: data,
            characteristicUUID: "2A19",
            packetCounter: nil,
            statusFlag: nil,
            deviceTimestamp: nil,
            additionalSensorData: nil
        )
    }
    
    // MARK: - Morpheus Proprietary Protocol Parsing
    
    /// Parse Morpheus proprietary data from characteristic FC20
    /// Format analysis of observed pattern: 01 0A C6 4E 4D 2C FB 02 8A 1E AF 3C 00 28
    func parseMorpheusFC20Data(_ data: Data) -> MorpheusData? {
        guard data.count >= 14 else { 
            logger.warning("FC20 data too short: \(data.count) bytes")
            return nil 
        }
        
        let bytes = [UInt8](data)
        
        // Parse the 14-byte Morpheus proprietary format
        let packetCounter = bytes[0]        // 0x01 - Packet counter/type
        let statusFlag = bytes[1]           // 0x0A - Status or mode flag
        
        // Bytes 2-5: Possible timestamp (little-endian)
        let timestampBytes = Data(bytes[2...5])
        let deviceTimestamp = timestampBytes.withUnsafeBytes { $0.load(as: UInt32.self) }
        
        // Bytes 6-7: Possible RR interval in milliseconds (little-endian)
        let rrIntervalRaw = UInt16(bytes[6]) | (UInt16(bytes[7]) << 8)
        let rrInterval = Int(rrIntervalRaw)
        
        // Calculate heart rate from RR interval if valid
        var heartRate: Int?
        if rrInterval > 0 && rrInterval < 5000 { // Reasonable RR interval range
            heartRate = 60000 / rrInterval // Convert to BPM
        }
        
        // Bytes 8-11: Additional sensor data or extended timestamp
        let additionalData = Data(bytes[8...11])
        
        // Bytes 12-13: Reserved or additional data
        // let reserved = bytes[12]
        let lastByte = bytes[13] // 0x28 = 40 decimal - could be heart rate
        
        logger.info("Parsed FC20 - Counter: \(packetCounter), Status: \(statusFlag), Timestamp: \(deviceTimestamp), RR: \(rrInterval)ms, HR: \(heartRate ?? -1)bpm, Last: \(lastByte)")
        
        return MorpheusData(
            timestamp: Date(),
            heartRate: heartRate,
            rrInterval: rrInterval,
            batteryLevel: nil,
            rawData: data,
            characteristicUUID: "FC20",
            packetCounter: packetCounter,
            statusFlag: statusFlag,
            deviceTimestamp: deviceTimestamp,
            additionalSensorData: additionalData
        )
    }
    
    // MARK: - Generic Parser Entry Point
    
    /// Main parsing function that routes data based on characteristic UUID
    func parseCharacteristicData(_ data: Data, characteristicUUID: String) -> MorpheusData? {
        switch characteristicUUID.uppercased() {
        case "2A37":
            return parseHeartRateMeasurement(data)
        case "2A19":
            return parseBatteryLevel(data)
        case "FC20":
            return parseMorpheusFC20Data(data)
        default:
            logger.debug("Unknown characteristic \(characteristicUUID), storing raw data")
            return MorpheusData(
                timestamp: Date(),
                heartRate: nil,
                rrInterval: nil,
                batteryLevel: nil,
                rawData: data,
                characteristicUUID: characteristicUUID,
                packetCounter: nil,
                statusFlag: nil,
                deviceTimestamp: nil,
                additionalSensorData: nil
            )
        }
    }
    
    // MARK: - Data Validation
    
    /// Validate that parsed heart rate is within reasonable bounds
    func isValidHeartRate(_ heartRate: Int) -> Bool {
        return heartRate >= 30 && heartRate <= 220
    }
    
    /// Validate that RR interval is within reasonable bounds
    func isValidRRInterval(_ rrInterval: Int) -> Bool {
        return rrInterval >= 250 && rrInterval <= 2000 // 30-240 BPM range
    }
    
    // MARK: - Device Information Parsing
    
    /// Parse device information strings (characteristics 2A25, 2A26, 2A27, 2A28)
    func parseDeviceInfoString(_ data: Data) -> String? {
        return String(data: data, encoding: .utf8)
    }
    
    /// Parse body sensor location (characteristic 2A38)
    func parseBodySensorLocation(_ data: Data) -> String? {
        guard data.count >= 1 else { return nil }
        
        let location = data[0]
        switch location {
        case 0: return "Other"
        case 1: return "Chest"
        case 2: return "Wrist"
        case 3: return "Finger"
        case 4: return "Hand"
        case 5: return "Ear Lobe"
        case 6: return "Foot"
        default: return "Unknown (\(location))"
        }
    }
}

// MARK: - Extensions for Data Analysis

extension MorpheusDataParser {
    
    /// Generate a detailed analysis report of the parsed data
    func generateAnalysisReport(for morpheusData: MorpheusData) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        let timestampString = formatter.string(from: morpheusData.timestamp)
        
        var report = "=== Morpheus Data Analysis ===\n"
        report += "Timestamp: \(timestampString)\n"
        report += "Characteristic: \(morpheusData.characteristicUUID)\n"
        report += "Raw Data: \(morpheusData.rawData.map { String(format: "%02X", $0) }.joined(separator: " "))\n"
        
        if let heartRate = morpheusData.heartRate {
            report += "Heart Rate: \(heartRate) bpm\n"
        }
        
        if let rrInterval = morpheusData.rrInterval {
            report += "RR Interval: \(rrInterval) ms\n"
        }
        
        if let batteryLevel = morpheusData.batteryLevel {
            report += "Battery Level: \(batteryLevel)%\n"
        }
        
        if let packetCounter = morpheusData.packetCounter {
            report += "Packet Counter: \(packetCounter)\n"
        }
        
        if let statusFlag = morpheusData.statusFlag {
            report += "Status Flag: 0x\(String(format: "%02X", statusFlag))\n"
        }
        
        if let deviceTimestamp = morpheusData.deviceTimestamp {
            report += "Device Timestamp: \(deviceTimestamp)\n"
        }
        
        if let additionalData = morpheusData.additionalSensorData {
            report += "Additional Data: \(additionalData.map { String(format: "%02X", $0) }.joined(separator: " "))\n"
        }
        
        return report
    }
}
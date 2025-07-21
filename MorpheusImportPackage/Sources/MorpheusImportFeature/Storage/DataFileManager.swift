import Foundation
import os.log

@MainActor
final class DataFileManager {
    nonisolated let logger = Logger(subsystem: "com.morpheusimport.app", category: "DataFileManager")
    
    // MARK: - File URLs
    private let documentsURL: URL
    private let morpheusDataURL: URL
    
    init() {
        documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        morpheusDataURL = documentsURL.appendingPathComponent("MorpheusData", isDirectory: true)
        
        createDirectoryIfNeeded()
    }
    
    // MARK: - Directory Management
    private func createDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(
                at: self.morpheusDataURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            logger.info("Created Morpheus data directory at \(self.morpheusDataURL.path)")
        } catch {
            logger.error("Failed to create data directory: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Session Management
    func createNewSession(deviceName: String) -> String {
        let timestamp = Date().formatted(.iso8601)
        let sessionID = "\(deviceName)_\(timestamp)"
        logger.info("Created new session: \(sessionID)")
        return sessionID
    }
    
    // MARK: - Raw Data Logging
    func logRawData(_ data: Data, 
                   characteristicUUID: String, 
                   sessionID: String,
                   timestamp: Date = Date()) async {
        let filename = "\(sessionID)_raw.csv"
        let fileURL = morpheusDataURL.appendingPathComponent(filename)
        
        let csvRow = formatCSVRow(
            timestamp: timestamp,
            characteristicUUID: characteristicUUID,
            data: data
        )
        
        await appendToFile(content: csvRow, fileURL: fileURL, isFirstWrite: !FileManager.default.fileExists(atPath: fileURL.path))
    }
    
    // MARK: - Binary Data Logging
    func logBinaryData(_ data: Data,
                      characteristicUUID: String,
                      sessionID: String,
                      timestamp: Date = Date()) async {
        let filename = "\(sessionID)_\(characteristicUUID)_binary.dat"
        let fileURL = morpheusDataURL.appendingPathComponent(filename)
        
        // Create a timestamped binary entry
        var logEntry = Data()
        
        // Add timestamp (8 bytes - Unix timestamp as Double)
        let timestampDouble = timestamp.timeIntervalSince1970
        withUnsafeBytes(of: timestampDouble) { bytes in
            logEntry.append(contentsOf: bytes)
        }
        
        // Add data length (4 bytes - UInt32)
        let dataLength = UInt32(data.count)
        withUnsafeBytes(of: dataLength.bigEndian) { bytes in
            logEntry.append(contentsOf: bytes)
        }
        
        // Add the actual data
        logEntry.append(data)
        
        await appendBinaryToFile(data: logEntry, fileURL: fileURL)
    }
    
    // MARK: - Analysis Data Logging
    func logAnalysis(_ analysis: String, sessionID: String) async {
        let filename = "\(sessionID)_analysis.txt"
        let fileURL = morpheusDataURL.appendingPathComponent(filename)
        
        let timestamp = Date().formatted(.iso8601)
        let analysisEntry = "[\(timestamp)] \(analysis)\n"
        
        await appendToFile(content: analysisEntry, fileURL: fileURL, isFirstWrite: false)
    }
    
    // MARK: - Heart Rate Logging
    func logHeartRate(_ heartRate: Int, sessionID: String, timestamp: Date = Date()) async {
        let filename = "\(sessionID)_heartrates.csv"
        let fileURL = morpheusDataURL.appendingPathComponent(filename)
        
        let csvRow = "\(timestamp.formatted(.iso8601)),\(heartRate)\n"
        let header = "Timestamp,HeartRate\n"
        
        await appendToFile(
            content: csvRow, 
            fileURL: fileURL, 
            isFirstWrite: !FileManager.default.fileExists(atPath: fileURL.path),
            header: header
        )
    }
    
    // MARK: - File Operations
    private func appendToFile(content: String, 
                            fileURL: URL, 
                            isFirstWrite: Bool, 
                            header: String? = nil) async {
        do {
            if isFirstWrite {
                // Create new file with header
                let initialContent = (header ?? createCSVHeader()) + content
                try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
                logger.info("Created new data file: \(fileURL.lastPathComponent)")
            } else {
                // Append to existing file
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                defer { fileHandle.closeFile() }
                
                fileHandle.seekToEndOfFile()
                if let data = content.data(using: .utf8) {
                    fileHandle.write(data)
                }
            }
        } catch {
            logger.error("Failed to write to file \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }
    
    private func appendBinaryToFile(data: Data, fileURL: URL) async {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                // Append to existing file
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                defer { fileHandle.closeFile() }
                
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
            } else {
                // Create new file
                try data.write(to: fileURL)
                logger.info("Created new binary data file: \(fileURL.lastPathComponent)")
            }
        } catch {
            logger.error("Failed to write binary data to \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Data Formatting
    private func formatCSVRow(timestamp: Date, characteristicUUID: String, data: Data) -> String {
        let hexString = data.map { String(format: "%02hhX", $0) }.joined(separator: " ")
        let asciiString = String(data: data, encoding: .ascii)?.replacingOccurrences(of: ",", with: "\\,") ?? "N/A"
        let binaryString = data.map { String($0, radix: 2).padded(toLength: 8, withPad: "0", startingAt: 0) }.joined(separator: " ")
        
        return "\(timestamp.formatted(.iso8601)),\(characteristicUUID),\(data.count),\(hexString),\(asciiString),\(binaryString)\n"
    }
    
    private func createCSVHeader() -> String {
        return "Timestamp,CharacteristicUUID,DataLength,HexData,ASCIIData,BinaryData\n"
    }
    
    // MARK: - File Management
    func getAllSessions() -> [String] {
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: morpheusDataURL.path)
            let sessions = Set(files.compactMap { filename -> String? in
                let components = filename.components(separatedBy: "_")
                if components.count >= 3 {
                    return "\(components[0])_\(components[1])_\(components[2])"
                }
                return nil
            })
            return Array(sessions).sorted()
        } catch {
            logger.error("Failed to list sessions: \(error.localizedDescription)")
            return []
        }
    }
    
    func getFileURL(for sessionID: String, type: DataFileType) -> URL {
        let filename: String
        switch type {
        case .raw:
            filename = "\(sessionID)_raw.csv"
        case .binary(let characteristicUUID):
            filename = "\(sessionID)_\(characteristicUUID)_binary.dat"
        case .analysis:
            filename = "\(sessionID)_analysis.txt"
        case .heartRates:
            filename = "\(sessionID)_heartrates.csv"
        }
        return morpheusDataURL.appendingPathComponent(filename)
    }
    
    func deleteSession(_ sessionID: String) async {
        let sessions = getAllSessions()
        let sessionFiles = sessions.filter { $0.hasPrefix(sessionID) }
        
        for session in sessionFiles {
            for fileType in [DataFileType.raw, .analysis, .heartRates] {
                let fileURL = getFileURL(for: session, type: fileType)
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    logger.info("Deleted file: \(fileURL.lastPathComponent)")
                } catch {
                    // File might not exist, which is okay
                }
            }
        }
    }
    
    func getDataDirectoryURL() -> URL {
        return morpheusDataURL
    }
    
    // MARK: - Export Functionality
    func exportSessionData(_ sessionID: String) -> [URL] {
        var exportURLs: [URL] = []
        
        for fileType in [DataFileType.raw, .analysis, .heartRates] {
            let fileURL = getFileURL(for: sessionID, type: fileType)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                exportURLs.append(fileURL)
            }
        }
        
        // Also include binary files
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: morpheusDataURL.path)
            let binaryFiles = files.filter { $0.hasPrefix(sessionID) && $0.hasSuffix("_binary.dat") }
            for filename in binaryFiles {
                exportURLs.append(morpheusDataURL.appendingPathComponent(filename))
            }
        } catch {
            logger.error("Failed to find binary files for session \(sessionID): \(error.localizedDescription)")
        }
        
        return exportURLs
    }
}

// MARK: - Supporting Types
enum DataFileType {
    case raw
    case binary(characteristicUUID: String)
    case analysis
    case heartRates
}

// MARK: - String Extension
private extension String {
    func padded(toLength length: Int, withPad pad: String, startingAt index: Int) -> String {
        return String(String(reversed()).padding(toLength: length, withPad: pad, startingAt: index).reversed())
    }
}
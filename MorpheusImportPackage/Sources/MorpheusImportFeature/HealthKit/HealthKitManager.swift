import Foundation
import HealthKit
import os.log

@Observable
@MainActor
final class HealthKitManager {
    nonisolated let logger = Logger(subsystem: "com.morpheusimport.app", category: "HealthKitManager")
    
    // MARK: - State
    var isAuthorized = false
    var authorizationStatus: HKAuthorizationStatus = .notDetermined
    
    // MARK: - HealthKit Store
    private let healthStore = HKHealthStore()
    
    // MARK: - Data Types
    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    private let heartRateVariabilityType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    
    private var typesToShare: Set<HKSampleType> {
        [heartRateType, heartRateVariabilityType]
    }
    
    private var typesToRead: Set<HKObjectType> {
        [heartRateType, heartRateVariabilityType]
    }
    
    // MARK: - Authorization
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("HealthKit not available on this device")
            throw HealthKitError.notAvailable
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            
            // Check authorization status
            authorizationStatus = healthStore.authorizationStatus(for: heartRateType)
            isAuthorized = authorizationStatus == .sharingAuthorized
            
            logger.info("HealthKit authorization completed. Status: \(String(describing: self.authorizationStatus))")
        } catch {
            logger.error("HealthKit authorization failed: \(error.localizedDescription)")
            throw HealthKitError.authorizationFailed(error)
        }
    }
    
    // MARK: - Writing Data
    func saveHeartRate(_ heartRate: Int, date: Date = Date()) async throws {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }
        
        let quantity = HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: Double(heartRate))
        let sample = HKQuantitySample(
            type: heartRateType,
            quantity: quantity,
            start: date,
            end: date,
            metadata: [
                HKMetadataKeyDeviceName: "Morpheus HRM",
                HKMetadataKeyExternalUUID: UUID().uuidString
            ]
        )
        
        do {
            try await healthStore.save(sample)
            logger.info("Saved heart rate: \(heartRate) bpm")
        } catch {
            logger.error("Failed to save heart rate: \(error.localizedDescription)")
            throw HealthKitError.saveFailed(error)
        }
    }
    
    func saveHeartRateVariability(_ hrv: Double, date: Date = Date()) async throws {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }
        
        let quantity = HKQuantity(unit: .secondUnit(with: .milli), doubleValue: hrv)
        let sample = HKQuantitySample(
            type: heartRateVariabilityType,
            quantity: quantity,
            start: date,
            end: date,
            metadata: [
                HKMetadataKeyDeviceName: "Morpheus HRM",
                HKMetadataKeyExternalUUID: UUID().uuidString
            ]
        )
        
        do {
            try await healthStore.save(sample)
            logger.info("Saved HRV: \(hrv) ms")
        } catch {
            logger.error("Failed to save HRV: \(error.localizedDescription)")
            throw HealthKitError.saveFailed(error)
        }
    }
    
    // MARK: - Batch Writing
    func saveHeartRateSamples(_ samples: [(heartRate: Int, date: Date)]) async throws {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }
        
        let hkSamples = samples.map { sample in
            let quantity = HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: Double(sample.heartRate))
            return HKQuantitySample(
                type: heartRateType,
                quantity: quantity,
                start: sample.date,
                end: sample.date,
                metadata: [
                    HKMetadataKeyDeviceName: "Morpheus HRM",
                    HKMetadataKeyExternalUUID: UUID().uuidString
                ]
            )
        }
        
        do {
            try await healthStore.save(hkSamples)
            logger.info("Saved \(hkSamples.count) heart rate samples")
        } catch {
            logger.error("Failed to save heart rate samples: \(error.localizedDescription)")
            throw HealthKitError.saveFailed(error)
        }
    }
    
    // MARK: - Reading Data (for verification)
    func fetchRecentHeartRates(limit: Int = 100) async throws -> [HeartRateSample] {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: nil,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }
                
                let heartRateSamples = (samples ?? []).compactMap { sample -> HeartRateSample? in
                    guard let quantitySample = sample as? HKQuantitySample else { return nil }
                    
                    let heartRate = quantitySample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
                    return HeartRateSample(
                        heartRate: Int(heartRate),
                        date: quantitySample.startDate,
                        deviceName: quantitySample.metadata?[HKMetadataKeyDeviceName] as? String
                    )
                }
                
                continuation.resume(returning: heartRateSamples)
            }
            
            healthStore.execute(query)
        }
    }
}

// MARK: - Supporting Types
enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case authorizationFailed(Error)
    case saveFailed(Error)
    case queryFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit access not authorized"
        case .authorizationFailed(let error):
            return "HealthKit authorization failed: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save to HealthKit: \(error.localizedDescription)"
        case .queryFailed(let error):
            return "Failed to query HealthKit: \(error.localizedDescription)"
        }
    }
}

struct HeartRateSample: Identifiable, Sendable {
    let id = UUID()
    let heartRate: Int
    let date: Date
    let deviceName: String?
}
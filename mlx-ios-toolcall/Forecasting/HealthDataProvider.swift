//
//  HealthDataProvider.swift
//  mlx-ios-toolcall
//
//  Reads real Health data (on-device, private) into time series for TimesFM.
//

import Foundation
import HealthKit

actor HealthDataProvider {
    private let store = HKHealthStore()

    enum HealthError: LocalizedError {
        case unavailable, noData
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Health data isn't available on this device (try a real iPhone)."
            case .noData:      return "No Health history found yet."
            }
        }
    }

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
        ]
    }

    /// Read auth status is hidden by Apple for privacy — if denied the query just returns no data.
    private func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthError.unavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Daily totals of a cumulative quantity → [TimeSeriesPoint], oldest first.
    private func dailyTotals(_ type: HKQuantityType, unit: HKUnit, days: Int) async throws -> [TimeSeriesPoint] {
        try await requestAuthorization()

        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { throw HealthError.noData }

        let query = HKStatisticsCollectionQuery(
            quantityType: type,
            quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: .now),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )

        return try await withCheckedThrowingContinuation { continuation in
            query.initialResultsHandler = { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                guard let results else { continuation.resume(throwing: HealthError.noData); return }
                var points: [TimeSeriesPoint] = []
                results.enumerateStatistics(from: start, to: end) { stat, _ in
                    let value = stat.sumQuantity()?.doubleValue(for: unit) ?? 0
                    points.append(TimeSeriesPoint(date: stat.startDate, value: value))
                }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    func dailySteps(days: Int = 90) async throws -> [TimeSeriesPoint] {
        try await dailyTotals(HKQuantityType(.stepCount), unit: .count(), days: days)
    }

    func dailyActiveEnergy(days: Int = 90) async throws -> [TimeSeriesPoint] {
        try await dailyTotals(HKQuantityType(.activeEnergyBurned), unit: .kilocalorie(), days: days)
    }

    func dailyDistance(days: Int = 90) async throws -> [TimeSeriesPoint] {
        try await dailyTotals(HKQuantityType(.distanceWalkingRunning), unit: .meterUnit(with: .kilo), days: days)
    }
}

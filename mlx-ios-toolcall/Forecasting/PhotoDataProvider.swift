//
//  PhotoDataProvider.swift
//  mlx-ios-toolcall
//
//  Reads photo timestamps (on-device) into a daily-count time series for TimesFM.
//

import Foundation
import Photos

actor PhotoDataProvider {
    enum PhotoError: LocalizedError {
        case notAuthorized
        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Photo library access was not granted."
            }
        }
    }

    private func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Photos taken per day over the last `days` days → [TimeSeriesPoint], oldest first.
    func dailyPhotoCounts(days: Int = 180) async throws -> [TimeSeriesPoint] {
        guard await requestAuthorization() else { throw PhotoError.notAuthorized }

        let calendar = Calendar.current
        let end = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return [] }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@",
                                        start as NSDate, Date() as NSDate)
        let assets = PHAsset.fetchAssets(with: options)

        var counts: [Date: Int] = [:]
        assets.enumerateObjects { asset, _, _ in
            if let date = asset.creationDate {
                counts[calendar.startOfDay(for: date), default: 0] += 1
            }
        }

        var points: [TimeSeriesPoint] = []
        var day = start
        while day < end {
            points.append(TimeSeriesPoint(date: day, value: Double(counts[day] ?? 0)))
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end
        }
        return points
    }
}

//
//  DemoForecastEngine.swift
//  mlx-ios-toolcall
//
//  Created by Serhat Akar on 04/09/2026.
//


import Foundation

enum DemoForecastEngine {
    static func makeForecast(now: Date = .now) -> ForecastResult {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        let history = (0..<64).map { index in
            let date = calendar.date(byAdding: .day, value: index - 63, to: today)!
            let value = 62.0
                + sin(Double(index) * 0.55) * 8.0
                + cos(Double(index) * 0.18) * 4.0

            return TimeSeriesPoint(date: date, value: value)
        }

        let forecast = (1...7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            let median = 62.0
                + sin(Double(63 + offset) * 0.55) * 8.0
                + cos(Double(63 + offset) * 0.18) * 4.0
            let uncertainty = 3.0 + Double(offset) * 0.8

            return ForecastPoint(
                date: date,
                lower: median - uncertainty,
                median: median,
                upper: median + uncertainty
            )
        }

        return ForecastResult(
            seriesName: "Demo signal",
            unit: "points",
            history: history,
            forecast: forecast
        )
    }
}

//
//  ForecastView.swift
//  mlx-ios-toolcall
//
//  Created by Serhat Akar on 04/09/2026.
//

import SwiftUI
import Charts

struct ForecastView: View {
    let result: ForecastResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.seriesName)
                        .font(.headline)

                    Text("Historical signal and \(result.forecast.count)-day forecast")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(result.unit)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(result.history) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                }

                ForEach(result.forecast) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Lower", point.lower),
                        yEnd: .value("Upper", point.upper)
                    )
                    .foregroundStyle(.purple.opacity(0.18))
                }

                ForEach(result.forecast) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Median", point.median)
                    )
                    .foregroundStyle(.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYAxisLabel(result.unit)
            .frame(height: 220)

            HStack(spacing: 16) {
                Label("History", systemImage: "circle.fill")
                    .foregroundStyle(.blue)

                Label("Forecast median", systemImage: "circle.fill")
                    .foregroundStyle(.purple)

                Label("p10–p90", systemImage: "rectangle.fill")
                    .foregroundStyle(.purple.opacity(0.35))
            }
            .font(.caption)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

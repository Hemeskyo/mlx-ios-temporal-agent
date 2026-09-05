//
//  PerformancePanel.swift
//  mlx-ios-toolcall
//

import SwiftUI
import Charts

/// Always-visible telemetry panel: generation speed + a live memory sparkline.
struct PerformancePanel: View {
    let metrics: Metrics?
    let memoryHistory: [Int]
    let memoryMB: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Performance", systemImage: "speedometer")
                    .font(.subheadline.bold())
                Spacer()
                Text(metrics.map { String(format: "%.2f s", $0.promptTime + $0.generateTime) } ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Speed stats
            HStack(spacing: 12) {
                stat("Prefill",
                     rate: metrics.map { Int($0.prefillTokensPerSecond) },
                     tokens: metrics?.promptTokens,
                     color: .blue)
                stat("Decode",
                     rate: metrics.map { Int($0.decodeTokensPerSecond) },
                     tokens: metrics?.generationTokens,
                     color: .green)
            }

            // Speed bar chart (zeroed + dimmed until first run)
            Chart {
                BarMark(x: .value("Phase", "Prefill"),
                        y: .value("tok/s", metrics?.prefillTokensPerSecond ?? 0))
                    .foregroundStyle(.blue)
                BarMark(x: .value("Phase", "Decode"),
                        y: .value("tok/s", metrics?.decodeTokensPerSecond ?? 0))
                    .foregroundStyle(.green)
            }
            .chartYScale(domain: 0...yMax)
            .frame(height: 70)
            .opacity(metrics == nil ? 0.3 : 1)

            Divider()

            // Live memory row: current usage + rolling sparkline
            HStack(spacing: 12) {
                Label("\(memoryMB) MB", systemImage: "memorychip")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.orange)
                Spacer()
                if !memoryHistory.isEmpty {
                    Chart(Array(memoryHistory.enumerated()), id: \.offset) { index, mb in
                        LineMark(x: .value("t", index), y: .value("MB", mb))
                            .foregroundStyle(.orange)
                        AreaMark(x: .value("t", index), y: .value("MB", mb))
                            .foregroundStyle(.orange.opacity(0.12))
                    }
                    .chartYScale(domain: 0...2500)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(width: 130, height: 32)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.06)))
    }

    private var yMax: Double {
        max(150, (metrics?.prefillTokensPerSecond ?? 0) + 20)
    }

    private func stat(_ label: String, rate: Int?, tokens: Int?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Text(rate.map { "\($0) tok/s" } ?? "—")
                .font(.callout.bold().monospacedDigit())
            Text(tokens.map { "\($0) tok" } ?? "—")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

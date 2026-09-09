//
//  OnboardingView.swift
//  mlx-ios-toolcall
//
//  Mandatory first-run flow: pull both on-device models — TimesFM first, then
//  LFM2 — with grounded, technical copy (the audience is MLX / AI / LiquidAI
//  people, so exact model IDs, quantization, sizes and provenance, no marketing).
//  Downloads only; the LFM↔TimesFM wiring lives elsewhere.
//

import SwiftUI

struct OnboardingView: View {
    let manager: ModelManager       // LFM2 (mlx-swift-lm)
    let timesFM: TimesFMManager     // TimesFM-3 (native Swift/MLX port)
    let onComplete: () -> Void

    private enum Step: Int, CaseIterable { case welcome, timesFM, lfm, ready }
    @State private var step: Step = .welcome

    var body: some View {
        VStack(spacing: 0) {
            progressDots
                .padding(.top, 10)

            // Content fills the screen and scrolls if needed…
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stepContent
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            // …CTA pinned at the bottom.
            cta
                .padding(.horizontal)
                .padding(.bottom, 10)
        }
    }

    // MARK: Content per step (no CTA — that lives in the pinned bar below)

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .welcome: welcomeContent
        case .timesFM: timesFMContent
        case .lfm:     lfmContent
        case .ready:   readyContent
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Temporal").font(.largeTitle.bold())
            Text("Two models, on-device via MLX (Apple Silicon / Metal). No server, no API.")
                .foregroundStyle(.secondary)

            specRow("LFM2.5-2.6B", "LiquidAI · 4-bit · base · general chat")
            specRow("TimesFM-3.0", "Google · native Swift/MLX port · zero-shot forecaster")

            Text("The LLM calls the forecaster as a tool. ~2 GB one-time (Hugging Face), then fully offline.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var timesFMContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(1, "TimesFM-3.0")
            specCard(
                id: "google/timesfm-3.0-pytorch",
                lines: [
                    "fp32 · ~1.3 GB",
                    "Decoder-only foundation model for time series.",
                    "Zero-shot — forecasts any structured series, no fitting.",
                    "Port: Hemeskyo/TimesFM-3-MLX-Swift · parity ~1e-6 vs PyTorch.",
                ]
            )
            timesFMAction
        }
    }

    private var lfmContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepHeader(2, "LFM2")
            specCard(
                id: "LiquidAI/LFM2.5-2.6B-MLX-4bit",
                lines: [
                    "4-bit MLX · ~1.5 GB",
                    "LFM2.5-2.6B base (LiquidAI, official).",
                    "Runs via mlx-swift-lm.",
                    "General chat. Switch to the tool-calling model in Settings for forecasting.",
                ]
            )
            lfmAction
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Both models resident — on-device via MLX", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("Inference runs locally (MLX / Metal). Nothing leaves the device.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            PerformancePanel(
                metrics: manager.lastMetrics,
                memoryHistory: manager.memoryHistory,
                memoryMB: manager.activeMemoryMB + manager.cacheMemoryMB
            )
            Text("tok/s appears after the first generation.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Pinned CTA per step

    @ViewBuilder private var cta: some View {
        switch step {
        case .welcome:
            primaryButton("Continue") { step = .timesFM }
        case .timesFM:
            primaryButton("Continue") { step = .lfm }
                .disabled(!timesFMReady)
        case .lfm:
            primaryButton("Continue") { step = .ready }
                .disabled(!lfmReady)
        case .ready:
            primaryButton("Enter") { onComplete() }
        }
    }

    // MARK: State-driven model actions

    private var timesFMReady: Bool { if case .ready = timesFM.state { return true }; return false }
    private var lfmReady: Bool { if case .ready = manager.state { return true }; return false }

    @ViewBuilder private var timesFMAction: some View {
        switch timesFM.state {
        case .idle:
            Button { Task { await timesFM.load() } } label: {
                actionLabel(timesFM.hasCachedWeights ? "Load from cache" : "Download checkpoint",
                            systemImage: timesFM.hasCachedWeights ? "memorychip.fill" : "arrow.down.circle.fill",
                            detail: timesFM.hasCachedWeights ? "cached" : "1.3 GB")
            }
            .buttonStyle(.borderedProminent)
        case .loading:
            loadingRow("Downloading & preparing TimesFM…", since: timesFM.loadStartedAt)
        case .ready:
            readyRow("TimesFM resident on device")
        case .failed(let message):
            failedRow(message) { Task { await timesFM.retryLoad() } }
        }
    }

    @ViewBuilder private var lfmAction: some View {
        switch manager.state {
        case .idle:
            Button { Task { await manager.load(.lfm2Base) } } label: {
                actionLabel(manager.hasCachedWeights ? "Load from cache" : "Download weights",
                            systemImage: manager.hasCachedWeights ? "memorychip.fill" : "arrow.down.circle.fill",
                            detail: manager.hasCachedWeights ? "cached" : "1.5 GB")
            }
            .buttonStyle(.borderedProminent)
        case .loading:
            loadingRow("Downloading & preparing LFM2…", since: nil)
        case .ready:
            readyRow("LFM2 resident on device")
        case .failed(let message):
            failedRow(message) { Task { await manager.retryLoad(.lfm2Base) } }
        }
    }

    // MARK: Building blocks

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: s == step ? 22 : 8, height: 8)
            }
        }
        .animation(.snappy, value: step)
    }

    private func stepHeader(_ index: Int, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.caption.bold().monospaced())
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(title).font(.title2.bold())
        }
    }

    private func specRow(_ id: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(id).font(.subheadline.bold().monospaced())
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func specCard(id: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(id)
                .font(.footnote.bold().monospaced())
                .textSelection(.enabled)
            ForEach(lines, id: \.self) { line in
                Text(line).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func actionLabel(_ title: String, systemImage: String, detail: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(detail).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadingRow(_ title: String, since start: Date?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProgressView()
                Text(title).font(.subheadline.weight(.semibold))
            }
            Text("First launch can take several minutes. Keep the app open, prefer Wi-Fi.")
                .font(.caption).foregroundStyle(.secondary)
            if let start {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Elapsed \(elapsed(since: start, now: context.date))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func readyRow(_ title: String) -> some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.green)
    }

    private func failedRow(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Download failed", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
            Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Button("Retry", action: retry).buttonStyle(.bordered)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

//
//  Benchmark.swift
//  mlx-ios-toolcall
//
//  Rigorous automated on-device comparison of the available models (general chat, no tools).
//  Methodology to keep it fair:
//   • N trials, averaged, with the min–max decode spread reported.
//   • Model order is ALTERNATED each trial → cancels the "second model runs hotter" bias.
//   • A cooldown between models and between prompts → limits thermal-throttling drift.
//   • A discarded warm-up generation after each load → no cold-cache penalty on the first prompt.
//

import SwiftUI
import UIKit
import Charts

@Observable
@MainActor
final class BenchmarkRunner {
    struct Row: Identifiable {
        let id = UUID()
        let trial: Int
        let model: LLMModel
        let prompt: String
        let prefillTps: Double
        let decodeTps: Double
        let seconds: Double
        let genTokens: Int
        let memoryMB: Int
        let output: String
    }

    struct Summary {
        let model: LLMModel
        let decodeTps: Double
        let decodeMedian: Double
        let decodeStd: Double
        let decodeMin: Double
        let decodeMax: Double
        let prefillTps: Double
        let seconds: Double
        let peakMB: Int
        let samples: Int
    }

    struct PromptStat: Identifiable {
        let id = UUID()
        let prompt: String
        let decodeTps: Double
        let seconds: Double
        let genTokens: Int
        let output: String
    }

    // MARK: Config
    static let trials = 5
    static let promptCooldown: Duration = .seconds(3)
    static let modelCooldown: Duration = .seconds(8)
    static let warmupPrompt = "Say hello in one short sentence."

    /// Same prompts for every model → a fair general-chat comparison (no tools).
    static let prompts = [
        "Explain what an API is in two sentences.",
        "Write a haiku about the ocean.",
        "What is 17 × 23? Show your reasoning step by step.",
        "Summarize the main causes of World War I in three bullet points.",
    ]

    /// Models to benchmark: official base LFM2 + MiniCPM (fair base-vs-base chat).
    /// The tool-calling fine-tune (.lfm2) is excluded so results aren't confounded by the FT.
    static let benchmarkModels: [LLMModel] = [.lfm2Base, .minicpm5]

    private(set) var rows: [Row] = []
    private(set) var isRunning = false
    private(set) var note = ""

    func run(on manager: ModelManager, models: [LLMModel] = BenchmarkRunner.benchmarkModels) async {
        guard !isRunning else { return }
        isRunning = true
        rows = []
        defer { isRunning = false }

        for trial in 1...Self.trials {
            // Alternate first-mover each trial so no model is systematically the "hot" one.
            let order = (trial % 2 == 0) ? Array(models.reversed()) : models
            for model in order {
                note = "Trial \(trial)/\(Self.trials) · cooling down…"
                try? await Task.sleep(for: Self.modelCooldown)

                note = "Trial \(trial)/\(Self.trials) · loading \(model.displayName)…"
                manager.unload()
                await manager.load(model)
                guard case .ready = manager.state else {
                    note = "\(model.displayName) failed to load — skipped."
                    continue
                }

                // Discarded warm-up: the first gen after a load is cold-cache-slow.
                note = "Trial \(trial)/\(Self.trials) · \(model.displayName) warm-up…"
                _ = await manager.benchmarkGenerate(prompt: Self.warmupPrompt)

                for (i, prompt) in Self.prompts.enumerated() {
                    note = "Trial \(trial)/\(Self.trials) · \(model.displayName) · prompt \(i + 1)/\(Self.prompts.count)"
                    try? await Task.sleep(for: Self.promptCooldown)
                    let output = await manager.benchmarkGenerate(prompt: prompt)
                    let m = manager.lastMetrics
                    rows.append(Row(
                        trial: trial,
                        model: model,
                        prompt: prompt,
                        prefillTps: m?.prefillTokensPerSecond ?? 0,
                        decodeTps: m?.decodeTokensPerSecond ?? 0,
                        seconds: (m?.promptTime ?? 0) + (m?.generateTime ?? 0),
                        genTokens: m?.generationTokens ?? 0,
                        memoryMB: manager.activeMemoryMB + manager.cacheMemoryMB,
                        output: output
                    ))
                }
            }
        }
        note = "Done"
        manager.unload()
    }

    // MARK: Aggregates

    var testedModels: [LLMModel] {
        var seen: [LLMModel] = []
        for r in rows where !seen.contains(r.model) { seen.append(r.model) }
        return seen
    }

    func rows(for model: LLMModel) -> [Row] { rows.filter { $0.model == model } }

    var summaries: [Summary] {
        testedModels.map { model in
            let r = rows(for: model)
            let dec = r.map { $0.decodeTps }
            return Summary(
                model: model,
                decodeTps: avg(dec),
                decodeMedian: median(dec),
                decodeStd: std(dec),
                decodeMin: dec.min() ?? 0,
                decodeMax: dec.max() ?? 0,
                prefillTps: avg(r.map { $0.prefillTps }),
                seconds: avg(r.map { $0.seconds }),
                peakMB: r.map { $0.memoryMB }.max() ?? 0,
                samples: r.count
            )
        }
    }

    func promptStats(for model: LLMModel) -> [PromptStat] {
        Self.prompts.map { prompt in
            let r = rows.filter { $0.model == model && $0.prompt == prompt }
            return PromptStat(
                prompt: prompt,
                decodeTps: avg(r.map { $0.decodeTps }),
                seconds: avg(r.map { $0.seconds }),
                genTokens: Int(avg(r.map { Double($0.genTokens) }).rounded()),
                output: r.last?.output ?? ""
            )
        }
    }

    private func avg(_ vals: [Double]) -> Double {
        vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
    }

    private func median(_ vals: [Double]) -> Double {
        guard !vals.isEmpty else { return 0 }
        let s = vals.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    private func std(_ vals: [Double]) -> Double {
        guard vals.count > 1 else { return 0 }
        let m = avg(vals)
        let variance = vals.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(vals.count - 1)
        return variance.squareRoot()
    }

    // MARK: Report

    func markdownReport() -> String {
        var s = "# On-device LLM benchmark\n\n"
        s += "iPhone · MLX (Apple Silicon). \(Self.prompts.count) prompts × \(Self.trials) trials per model · reasoning on (enable_thinking), no tools.\n"
        s += "Method: alternating model order per trial, cooldowns between runs, one discarded warm-up per load.\n\n"
        s += "## Summary (\(Self.trials) trials)\n\n"
        s += "| Model | decode tok/s (median ± sd) | min–max | prefill | avg latency | peak mem | samples |\n"
        s += "|---|---|---|---|---|---|---|\n"
        for sum in summaries {
            s += "| \(sum.model.displayName) | \(f(sum.decodeMedian)) ± \(f(sum.decodeStd)) | \(f(sum.decodeMin))–\(f(sum.decodeMax)) | \(f(sum.prefillTps)) | \(f(sum.seconds))s | \(sum.peakMB) MB | \(sum.samples) |\n"
        }
        s += "\n## Per-prompt detail (averaged)\n\n"
        for model in testedModels {
            s += "### \(model.displayName)\n\n"
            for st in promptStats(for: model) {
                s += "- **\(st.prompt)**\n"
                s += "  - \(f(st.decodeTps)) tok/s · ~\(st.genTokens) tokens · \(f(st.seconds))s\n"
                s += "  - _\(st.output.replacingOccurrences(of: "\n", with: " "))_\n"
            }
            s += "\n"
        }
        return s
    }

    func f(_ d: Double) -> String { String(format: "%.1f", d) }
}

struct BenchmarkView: View {
    let manager: ModelManager
    var onClose: () -> Void
    @State private var runner = BenchmarkRunner()

    var body: some View {
        NavigationStack {
            Group {
                if runner.rows.isEmpty && !runner.isRunning {
                    startScreen
                } else {
                    resultsScreen
                }
            }
            .navigationTitle("Benchmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { onClose() }.disabled(runner.isRunning)
                }
            }
        }
    }

    private var startScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "speedometer")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("Compare models on-device").font(.title3.bold())
            Text("Runs \(BenchmarkRunner.prompts.count) prompts × \(BenchmarkRunner.trials) trials on each model (\(BenchmarkRunner.benchmarkModels.map { $0.displayName }.joined(separator: ", "))). Alternates order, cools down between runs, and discards a warm-up pass — so tok/s, latency and memory are fair. Takes several minutes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await runner.run(on: manager) }
            } label: {
                Label("Start benchmark", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    @ViewBuilder private var chartsSection: some View {
        if !runner.rows.isEmpty {
            Section("Decode · tok/s") {
                Chart(runner.summaries, id: \.model) { s in
                    BarMark(
                        x: .value("Model", s.model.displayName),
                        y: .value("tok/s", s.decodeMedian)
                    )
                    .foregroundStyle(by: .value("Model", s.model.displayName))
                    .annotation(position: .top) {
                        Text(runner.f(s.decodeMedian)).font(.caption2.monospacedDigit())
                    }
                    // Whisker = min–max spread across trials.
                    RuleMark(
                        x: .value("Model", s.model.displayName),
                        yStart: .value("min", s.decodeMin),
                        yEnd: .value("max", s.decodeMax)
                    )
                    .foregroundStyle(.primary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartLegend(.hidden)
                .frame(height: 200)
            }
            Section("Latency · s") {
                Chart(runner.summaries, id: \.model) { s in
                    BarMark(
                        x: .value("Model", s.model.displayName),
                        y: .value("s", s.seconds)
                    )
                    .foregroundStyle(by: .value("Model", s.model.displayName))
                    .annotation(position: .top) {
                        Text("\(runner.f(s.seconds))s").font(.caption2.monospacedDigit())
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 180)
            }
        }
    }

    private var resultsScreen: some View {
        List {
            if runner.isRunning {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(runner.note).font(.callout)
                    }
                }
            }

            chartsSection

            Section("Summary (\(BenchmarkRunner.trials) trials)") {
                ForEach(runner.summaries, id: \.model) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.model.displayName).font(.headline)
                        Text("\(runner.f(s.decodeMedian)) ± \(runner.f(s.decodeStd)) tok/s · \(runner.f(s.decodeMin))–\(runner.f(s.decodeMax))")
                            .font(.caption.monospacedDigit())
                        Text("\(runner.f(s.prefillTps)) prefill · \(runner.f(s.seconds))s avg · \(s.peakMB) MB peak · \(s.samples) samples")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(runner.testedModels, id: \.self) { model in
                Section(model.displayName) {
                    ForEach(runner.promptStats(for: model)) { st in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(st.prompt).font(.subheadline.weight(.medium))
                            Text("\(runner.f(st.decodeTps)) tok/s · ~\(st.genTokens) tok · \(runner.f(st.seconds))s")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(st.output)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                    }
                }
            }

            if !runner.isRunning && !runner.rows.isEmpty {
                Section {
                    ShareLink(item: runner.markdownReport()) {
                        Label("Export report (Markdown)", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = runner.markdownReport()
                    } label: {
                        Label("Copy report", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}

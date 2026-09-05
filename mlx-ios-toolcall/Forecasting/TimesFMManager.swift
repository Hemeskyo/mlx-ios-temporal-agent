//
//  TimesFMManager.swift
//  mlx-ios-toolcall
//
//  Created by Serhat Akar on 04/09/2026.
//


import Foundation
import Observation
import TimesFMMLX
import MLX

@Observable
@MainActor

final class TimesFMManager{
    enum State{
        case idle
        case loading
        case ready
        case failed(String)
    }
    
    private(set) var state:State = .idle
    private(set) var loadStartedAt: Date?
    private(set) var hasCachedWeights: Bool
    
    private let engine = TimesFMEngine()
    private let health = HealthDataProvider()
    private let photos = PhotoDataProvider()
    private let wiki = WikipediaDataProvider()
    private(set) var latestForecast: ForecastResult?
    private(set) var isForecasting = false
    private(set) var forecastError: String?

    // Live pipeline trace (LFM → tool → data → TimesFM), rendered in the chat.
    struct TraceStep: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let icon: String
    }
    private(set) var trace: [TraceStep] = []
    func resetTrace() { trace = [] }
    func pushStep(_ label: String, icon: String) { trace.append(TraceStep(label: label, icon: icon)) }
    func clearForecast() { latestForecast = nil; forecastError = nil }

    init() {
        hasCachedWeights = Self.cachedWeightsExist()
    }
    
    
    func load() async {
        guard case .idle = state else {return}
        
        state = .loading
        loadStartedAt = .now
        
        do {
            try await engine.load()
            state = .ready
            loadStartedAt = nil
            hasCachedWeights = true
        }
        catch
        {
            state = .failed(error.localizedDescription)
            loadStartedAt = nil
        }
    }

    func retryLoad() async {
        guard case .failed = state else { return }
        state = .idle
        await load()
    }

    private static func cachedWeightsExist() -> Bool {
        guard let cachesDirectory = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return false
        }

        let weightsURL = cachesDirectory
            .appendingPathComponent("TimesFMMLX", isDirectory: true)
            .appendingPathComponent("google--timesfm-3.0-pytorch", isDirectory: true)
            .appendingPathComponent("main", isDirectory: true)
            .appendingPathComponent("model.safetensors", isDirectory: false)

        guard FileManager.default.fileExists(atPath: weightsURL.path) else { return false }
        let size = (try? weightsURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0
    }
    
    func forecast(
        seriesName: String,
        unit: String,
        history: [TimeSeriesPoint],
        horizon: Int
    ) async {
        guard case .ready = state else { return }

        isForecasting = true
        forecastError = nil

        defer { isForecasting = false }

        do {
            latestForecast = try await engine.forecast(
                seriesName: seriesName,
                unit: unit,
                history: history,
                horizon: horizon
            )
        } catch {
            forecastError = error.localizedDescription
        }
    }
    
    /// Tool entry point: forecast a named metric and return a short text summary.
    /// Phase 1 uses the demo series; Phase 2 swaps in real data (HealthKit).
    /// Also updates `latestForecast` so the chat can draw the chart.
    func runForecast(metric: String, horizon: Int) async -> String {
        guard case .ready = state else { return "TimesFM isn't loaded yet." }

        let m = metric.lowercased()
        let history: [TimeSeriesPoint]
        let unit: String
        let label: String
        let source: String

        do {
            if m.contains("step") {
                history = try await health.dailySteps(days: 90);        unit = "steps/day";  label = "steps";         source = "HealthKit"
            } else if m.contains("distance") {
                history = try await health.dailyDistance(days: 90);     unit = "km/day";     label = "distance";      source = "HealthKit"
            } else if m.contains("energy") || m.contains("calor") {
                history = try await health.dailyActiveEnergy(days: 90); unit = "kcal/day";   label = "active energy"; source = "HealthKit"
            } else if m.contains("photo") {
                history = try await photos.dailyPhotoCounts(days: 180); unit = "photos/day"; label = "photos";        source = "PhotoKit"
            } else {
                let demo = DemoForecastEngine.makeForecast()   // fallback for unwired metrics
                history = demo.history; unit = demo.unit; label = metric; source = "demo"
            }
        } catch {
            return "Couldn't read \(metric): \(error.localizedDescription)"
        }

        guard history.count >= 32 else {
            return "Not enough history for \(label) yet (need ≥ 32 days)."
        }

        pushStep("Read \(label) · \(source)", icon: "externaldrive.fill")
        pushStep("TimesFM decode", icon: "chart.xyaxis.line")
        await forecast(seriesName: label, unit: unit, history: history, horizon: max(1, horizon))
        Memory.clearCache()   // free TimesFM's transient MLX buffers (both models are resident)
        pushStep("Done", icon: "checkmark.seal.fill")

        guard let f = latestForecast, let last = f.forecast.last else {
            return forecastError ?? "Forecast failed."
        }
        let end = Int(last.median.rounded())
        let lo = Int(last.lower.rounded())
        let hi = Int(last.upper.rounded())
        return "\(label): median ≈ \(end) \(unit) at +\(f.forecast.count) (band \(lo)–\(hi))."
    }

    /// Forecast public interest in a topic from its daily Wikipedia pageviews (web data).
    func runWebForecast(topic: String, horizon: Int) async -> String {
        guard case .ready = state else { return "TimesFM isn't loaded yet." }
        guard !topic.trimmingCharacters(in: .whitespaces).isEmpty else { return "No topic provided." }

        let title: String
        let history: [TimeSeriesPoint]
        do {
            (title, history) = try await wiki.dailyPageviews(topic: topic, days: 120)
        } catch {
            return "Couldn't fetch Wikipedia data for \"\(topic)\": \(error.localizedDescription)"
        }
        guard history.count >= 32 else {
            return "Not enough Wikipedia history for \"\(title)\" (need ≥ 32 days)."
        }

        pushStep("Read \"\(title)\" · Wikipedia", icon: "globe")
        pushStep("TimesFM decode", icon: "chart.xyaxis.line")
        await forecast(seriesName: title, unit: "views/day", history: history, horizon: max(1, horizon))
        Memory.clearCache()
        pushStep("Done", icon: "checkmark.seal.fill")

        guard let f = latestForecast, let last = f.forecast.last else {
            return forecastError ?? "Forecast failed."
        }
        let end = Int(last.median.rounded())
        let lo = Int(last.lower.rounded())
        let hi = Int(last.upper.rounded())
        return "\(title): median ≈ \(end) views/day at +\(f.forecast.count) (band \(lo)–\(hi))."
    }


}

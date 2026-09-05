//
//  ModelManager.swift
//  mlx-ios-toolcall
//

import Foundation
import MLXLMCommon
import MLXLLM
import MLX
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Owns the on-device model and drives all model work (loading + generation + memory).
@Observable
@MainActor
final class ModelManager {
    enum State {
        case idle
        case loading(Double)
        case ready(ModelContainer)
        case failed(String)
    }

    /// What one turn produced: a tool result, or a plain chat answer.
    enum Reply {
        case tool(String)
        case chat(String)
    }

    /// Routes the model: call a tool only when it fits, otherwise answer in chat.
    static let systemPrompt = """
        You are a helpful on-device assistant. Your ONLY tools are: create_reminder, \
        schedule_calendar_event, send_message, start_timer, open_maps, forecast, and forecast_web. \
        There is NO general web search or browser — do not invent one. \
        Call `forecast` for the user's own on-device metrics (steps, active energy, distance, photos). \
        Call `forecast_web` to predict public interest in a topic via its Wikipedia pageviews \
        (the `topic` is a Wikipedia article title, e.g. "ChatGPT"). \
        Call a tool ONLY when the request clearly maps to one. For general knowledge, facts, math, \
        or casual chat, answer directly from your own knowledge in plain text. Never invent tools.
        """


    private(set) var state: State = .idle
    private(set) var lastMetrics: Metrics?
    var timesFM: TimesFMManager?

    static let modelId = "Hskyto/lfm2.5-2.6b-toolcall-mlx-q4"
    /// True when the LFM2 weights are already on disk (so we can skip the download prompt).
    private(set) var hasCachedWeights = ModelManager.cachedWeightsExist()

    // MARK: Sampling parameters (bound to the Settings sheet)
    var temperature: Float = 0.6
    var topP: Float = 1.0
    var topK: Int = 0
    var maxTokens: Int = 256

    // MARK: Memory controls
    /// User-set cap on the MLX buffer cache (MB); applied instantly via didSet.
    var cacheLimitMB : Int = 64 {
        didSet {
            Memory.cacheLimit = cacheLimitMB * 1024 * 1024
        }
    }

    /// When true, free the MLX cache after every generation (safe default).
    var autoClearCache = true

    private(set) var activeMemoryMB = 0
    private(set) var cacheMemoryMB = 0
    private(set) var memoryHistory: [Int] = []   // total MLX memory (MB) over time

    /// Manually free the MLX buffer cache (handy when auto-clear is off).
    func clearCacheNow() {
        Memory.clearCache()
        refreshMemory()
    }

    /// Snapshot current MLX active/cache memory (MB) into observable state.
    func refreshMemory() {
        activeMemoryMB = Memory.activeMemory / (1024*1024)
        cacheMemoryMB = Memory.cacheMemory / (1024*1024)
    }

    /// Append current total MLX memory to the rolling history that feeds the live graph.
    func sampleMemory() {
            refreshMemory()
            memoryHistory.append(activeMemoryMB + cacheMemoryMB)
            if memoryHistory.count > 80 { memoryHistory.removeFirst() }   // keep last 80 samples
        }

    /// Background loop that samples memory ~twice a second so the UI graph stays live.
    private func startMemoryMonitor() {
           Task {
               while true {
                   sampleMemory()
                   try? await Task.sleep(for: .milliseconds(500))
               }
           }
       }

    /// Downloads (first launch) and loads the model into memory.
    func load() async {
        guard case .idle = state else { return }
        Memory.cacheLimit = cacheLimitMB * 1024 * 1024
        state = .loading(0)

        let configuration = ModelConfiguration(
            id: Self.modelId,
            toolCallFormat: .lfm2
        )

        do {
            let container = try await LLMModelFactory.shared.loadContainer(from: #hubDownloader(), using: #huggingFaceTokenizerLoader(), configuration: configuration)
            {progress in
                Task {
                    @MainActor in self.state = .loading(progress.fractionCompleted)
                }}
            state = .ready(container)
            hasCachedWeights = true
            startMemoryMonitor()
        }
        catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Reset after a failed load so the user can retry the download.
    func retryLoad() async {
        guard case .failed = state else { return }
        state = .idle
        await load()
    }

    /// Best-effort: does the LFM2 repo already exist in the Hugging Face cache?
    private static func cachedWeightsExist() -> Bool {
        let fm = FileManager.default
        var bases: [URL] = []
        if let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            bases.append(docs.appendingPathComponent("huggingface/models", isDirectory: true))
        }
        if let caches = try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            bases.append(caches.appendingPathComponent("huggingface/models", isDirectory: true))
            bases.append(caches.appendingPathComponent("models", isDirectory: true))
        }
        for base in bases {
            let dir = base.appendingPathComponent(modelId, isDirectory: true)
            if let files = try? fm.contentsOfDirectory(atPath: dir.path),
               files.contains(where: { $0.hasSuffix(".safetensors") }) {
                return true
            }
        }
        return false
    }

    /// Strips the <think>…</think> reasoning, keeping only the user-facing answer.
    private func stripThinking(_ text: String) -> String {
        if let range = text.range(of: "</think>") {
            return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Answers `prompt`. In fast mode, retries once with reasoning if the quick pass fires no tool.
    func respond(to prompt: String, thinking: Bool) async -> Reply {
        timesFM?.resetTrace()
        timesFM?.pushStep("LFM2 reasoning", icon: "brain")
        if thinking {
            return await runModel(prompt: prompt, thinking: true)
        }
        let fast = await runModel(prompt: prompt, thinking: false)
        if case .tool = fast {return fast}
        return await runModel(prompt: prompt, thinking: true)
    }

    /// One generation pass: system+user chat with tools, streamed → tool result or chat answer.
    private func runModel(prompt: String, thinking: Bool) async -> Reply {
        guard case .ready(let container) = state else { return .chat("Model not ready.") }
        defer{
            if autoClearCache { Memory.clearCache()}
            refreshMemory()
        }

        let params = GenerateParameters(
            maxTokens: maxTokens,
            temperature: temperature,
            topP:topP,
            topK: topK,
            )

        let userInput = UserInput(
            chat: [.system(Self.systemPrompt), .user(prompt)],
            tools: allToolSchemas,
            additionalContext: ["enable_thinking": thinking]
        )

        do {
            let lmInput = try await container.prepare(input: userInput)
            let stream = try await container.generate(input: lmInput, parameters: params)

            var results: [String] = []
            var raw = ""
            for await event in stream {
                switch event {
                case .info(let info):
                    lastMetrics = Metrics(
                        promptTokens: info.promptTokenCount,
                        generationTokens: info.generationTokenCount,
                        prefillTokensPerSecond:info.promptTokensPerSecond,
                        decodeTokensPerSecond:info.tokensPerSecond,
                        promptTime: info.promptTime,
                        generateTime: info.generateTime
                    )
                // The model chose to call a tool → run it. This is where `forecast`
                // reaches TimesFM. Results are shown directly (no second LLM turn).
                case .toolCall(let call):
                    if let output = await dispatch(call, context: ToolContext(timesFM: timesFM)) {
                        results.append(output)
                    }
                case .chunk(let text):
                    raw+=text
                }
            }

            if results.isEmpty {
                let answer = stripThinking(raw)
                return .chat(answer.isEmpty ? "No response" : answer)
            }

            return .tool(results.joined(separator: "\n"))

        }  catch  {
            return .chat("Error: \(error.localizedDescription)")
        }

    }
}

/// Unwraps a JSONValue into a plain display string.
extension JSONValue {
    var displayString: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .null: return "null"
        case .array, .object: return "\(anyValue)"
        }
    }
}

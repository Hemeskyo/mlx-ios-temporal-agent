//
//  ModelManager.swift
//  mlx-ios-toolcall
//

import Foundation
import MLXLMCommon
import MLXLLM
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Owns the on-device model and drives all model work (loading + generation).
@Observable
@MainActor
final class ModelManager {
    enum State {
        case idle
        case loading(Double)
        case ready(ModelContainer)
        case failed(String)
    }
    
    private(set) var state: State = .idle
    private(set) var lastMetrics: Metrics?
    
    /// Downloads (first launch) and loads the model into memory.
    func load() async {
        guard case .idle = state else { return }
        state = .loading(0)
        
        let configuration = ModelConfiguration(
            id: "Hskyto/lfm2.5-2.6b-toolcall-mlx-q4",
            toolCallFormat: .lfm2
        )
        
        do {
            let container = try await LLMModelFactory.shared.loadContainer(from: #hubDownloader(), using: #huggingFaceTokenizerLoader(), configuration: configuration)
            {progress in
                Task {
                    @MainActor in self.state = .loading(progress.fractionCompleted)
                }}
            state = .ready(container)
        }
        catch {
            state = .failed(error.localizedDescription)
        }
    }
    
    /// Runs the model on `prompt` and returns the tool call(s) it produced.
    func respond(to prompt: String) async -> String {
        guard case .ready(let container) = state else { return "Model not ready." }
        
        let userInput = UserInput(
            prompt: .text(prompt),
            tools: allToolSchemas
        )
        do {
            let lmInput = try await container.prepare(input: userInput)
            let stream = try await container.generate(input: lmInput, parameters: GenerateParameters(maxTokens: 256))
            
            var results: [String] = []
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
                case .toolCall(let call):
                    results.append(await dispatch(call))
                case .chunk:
                    break
                }
            }
            return results.isEmpty ? "No tool call made this time." : results.joined(separator: "\n")
            
        } catch  {
            return "Error: \(error.localizedDescription)"
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

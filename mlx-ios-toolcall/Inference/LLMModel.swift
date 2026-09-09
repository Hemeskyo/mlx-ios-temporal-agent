//
//  LLMModel.swift
//  mlx-ios-toolcall
//

import MLXLMCommon

/// The on-device chat models the app can run. Single source of truth for everything
/// that varies between them (repo id, display name, tool-call format, tool support).
/// Pure data — depends on nothing else in the app, so nothing changes until it's wired in.
enum LLMModel: String, CaseIterable, Identifiable {
    case lfm2
    case lfm2Base
    case minicpm5

    /// Stable identity for SwiftUI Picker / ForEach.
    var id: String { rawValue }

    /// Hugging Face repo the MLX weights are pulled from.
    var repoId: String {
        switch self {
        case .lfm2:     return "Hskyto/lfm2.5-2.6b-toolcall-mlx-q4"
        case .lfm2Base: return "LiquidAI/LFM2.5-2.6B-MLX-4bit"
        case .minicpm5: return "openbmb/MiniCPM5-2B-MLX"
        }
    }

    /// Name shown in the UI (Settings picker, etc.).
    var displayName: String {
        switch self {
        case .lfm2:     return "LFM2 2.6B (FT)"
        case .lfm2Base: return "LFM2 2.6B (base)"
        case .minicpm5: return "MiniCPM5 2B"
        }
    }

    /// How the library parses the tool calls this model emits.
    var toolCallFormat: ToolCallFormat {
        switch self {
        case .lfm2:     return .lfm2
        case .lfm2Base: return .lfm2
        case .minicpm5: return .json
        }
    }

    /// Whether we route tool calls to this model. MiniCPM5 emits XML-style calls that
    /// the library's `.json` parser doesn't read yet, so v1 runs it chat-only.
    var supportsTools: Bool {
        switch self {
        case .lfm2:     return true
        case .lfm2Base: return false
        case .minicpm5: return false
        }
    }
}

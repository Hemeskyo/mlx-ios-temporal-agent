//
//  ContentView.swift
//  mlx-ios-toolcall
//

import SwiftUI
import Charts

/// Root view: draws a screen per model state and sends prompts to the model.
struct ContentView: View {
    @State private var manager = ModelManager()
    @State private var prompt = "Remind me to call Dad at 7pm"
    @State private var result = ""
    @State private var isGenerating = false
    
    var body: some View {
        VStack(spacing: 20) {
            switch manager.state {
            case .idle:
                Button("Load model") {
                    Task { await manager.load() }
                }
                
            case .loading:
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Setting up the model")
                        .font(.headline)
                    Text("The first launch downloads the model once.\nThis can take a few minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 280)
                .padding()
                
            case .ready:
                VStack(spacing: 16) {
                    TextField("Ask something…", text: $prompt)
                        .textFieldStyle(.roundedBorder)
                    
                    Button(isGenerating ? "Thinking…" : "Send") {
                        Task {
                            isGenerating = true
                            result = await manager.respond(to: prompt)
                            isGenerating = false
                        }
                    }
                    .disabled(isGenerating)
                    
                    if !result.isEmpty {
                        Text(result)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    
                    if let m = manager.lastMetrics {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Performance").font(.caption).bold()
                            Text("Prefill: \(m.promptTokens) tok · \(m.prefillTokensPerSecond, specifier: "%.1f") tok/s")
                            Text("Decode: \(m.generationTokens) tok · \(m.decodeTokensPerSecond, specifier: "%.1f") tok/s")
                            Text("Total: \(m.promptTime + m.generateTime, specifier: "%.2f") s")
                            Chart {
                                BarMark(x: .value("Phase", "Prefill"),
                                        y: .value("tok/s", m.prefillTokensPerSecond)
                                ) .foregroundStyle(by: .value("Phase", "Prefill"))
                                BarMark(x: .value("Phase", "Decode"),
                                        y: .value("tok/s", m.decodeTokensPerSecond)) .foregroundStyle(by: .value("Phase", "Decode"))
                                
                            }
                            .frame(height: 120)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
                
            case .failed(let message):
                Text("Error \(message)").foregroundStyle(.red)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

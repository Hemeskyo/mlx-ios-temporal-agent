//
//  ContentView.swift
//  mlx-ios-toolcall
//

import SwiftUI

/// Root view: draws a screen per model state and sends prompts to the model.
struct ContentView: View {
    @State private var manager = ModelManager()
    @State private var prompt = "Remind me to call Dad at 7pm"
    @State private var result = ""
    @State private var isGenerating = false
    @State private var thinkingEnabled = false
    @State private var showSettings = false
    @FocusState private var promptFocused: Bool
    
    
    var body: some View {
        NavigationStack {
            Group {
                switch manager.state {
                case .idle:    idleView
                case .loading: loadingView
                case .ready:   readyView
                case .failed(let message):
                    ContentUnavailableView(
                        "Couldn't load the model",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                }
            }
            .navigationTitle("Tool-Call LLM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .ready = manager.state {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(manager: manager) }
        }
    }
    
    // MARK: Idle
    
    private var idleView: some View {
        VStack(spacing: 16) {
            Text("On-device tool-calling assistant")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("Load model") { Task { await manager.load() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: Loading
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Setting up the model").font(.headline)
            Text("The first launch downloads the model once.\nThis can take a few minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: Ready
    
    private var readyView: some View {
        ScrollView {
            VStack(spacing: 16) {
                inputCard
                if !result.isEmpty { resultCard }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture { promptFocused = false }
        .safeAreaInset(edge: .bottom) {
            PerformancePanel(
                metrics: manager.lastMetrics,
                memoryHistory: manager.memoryHistory,
                memoryMB: manager.activeMemoryMB + manager.cacheMemoryMB
            )
            .padding(.bottom, 6)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    
    private var inputCard: some View {
        VStack(spacing: 14) {
            TextField("Ask something…", text: $prompt, axis: .vertical)
                .lineLimit(1...4)
                .focused($promptFocused)
            
            Divider()
            
            Toggle(isOn: $thinkingEnabled) {
                Label("Reasoning", systemImage: "brain")
                    .font(.subheadline)
            }
            
            Button {
                promptFocused = false
                Task {
                    isGenerating = true
                    
                    let reply = await manager.respond(to: prompt, thinking: thinkingEnabled)
                    switch reply {
                    case .tool(let text), .chat(let text): result = text
                    }
                    isGenerating = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isGenerating { ProgressView().tint(.white) }
                    Text(isGenerating ? "Thinking…" : "Send")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isGenerating || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
    
    private var resultCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text(result)
                .font(.callout)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

#Preview {
    ContentView()
}

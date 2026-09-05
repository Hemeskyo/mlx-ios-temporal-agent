//
//  ContentView.swift
//  mlx-ios-toolcall
//

import SwiftUI

/// Root view: draws a screen per model state and sends prompts to the model.
struct ContentView: View {
    @State private var manager = ModelManager()
    @State private var timesFM = TimesFMManager()
    @State private var prompt = "Remind me to call Dad at 7pm"
    @State private var result = ""
    @State private var isGenerating = false
    @State private var thinkingEnabled = false
    @State private var showSettings = false
    @State private var showPerformance = false
    @AppStorage("didCompleteOnboarding") private var didOnboard = false
    @FocusState private var promptFocused: Bool
    
    private let demoForecast = DemoForecastEngine.makeForecast()
    
    private func submit(_ text: String) {
        prompt = text
        promptFocused = false
        result = ""                 // clear the previous answer…
        timesFM.clearForecast()     // …and the previous chart before a new run
        Task {
            isGenerating = true
            let reply = await manager.respond(to: text, thinking: thinkingEnabled)
            switch reply { case .tool(let t), .chat(let t): result = t }
            isGenerating = false
        }
    }
    
    /// Show onboarding only on a genuine first run — skip it once both models are cached.
    private var needsOnboarding: Bool {
        !didOnboard && !(timesFM.hasCachedWeights && manager.hasCachedWeights)
    }

    private var bothReady: Bool {
        if case .ready = timesFM.state, case .ready = manager.state { return true }
        return false
    }

    private var anyFailed: Bool {
        if case .failed = timesFM.state { return true }
        if case .failed = manager.state { return true }
        return false
    }

    /// Returning-launch splash: load both cached models into memory, then the app opens.
    private var warmingUpView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Warming up models").font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await warmUp() }
    }

    private var warmFailedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle).foregroundStyle(.orange)
            Text("Couldn't warm up the models").font(.headline)
            Button("Retry") {
                Task { await timesFM.retryLoad(); await manager.retryLoad() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// Load both cached models sequentially (bounds peak RAM vs. loading in parallel).
    private func warmUp() async {
        await timesFM.load()
        await manager.load()
    }

    var body: some View {
        NavigationStack {
            // App flow: first-run onboarding (download models) → warming up (load from
            // cache on later launches) → the chat once both models are resident.
            Group {
                if needsOnboarding {
                    OnboardingView(manager: manager, timesFM: timesFM) {
                        didOnboard = true
                    }
                } else if bothReady {
                    readyView
                } else if anyFailed {
                    warmFailedView
                } else {
                    warmingUpView
                }
            }
            .navigationTitle(bothReady ? "Temporal" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if bothReady {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(manager: manager) }
            .task { manager.timesFM = timesFM }
            .onChange(of: bothReady) { _, ready in
                if ready { didOnboard = true }   // never show onboarding again once both loaded
            }
        }
    }
    
    // MARK: Idle
    
    private var idleView: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("On-device temporal intelligence")
                        .font(.title2.weight(.bold))
                    Text("Language reasoning and forecasting, both fully local.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                languageModelControl
                timesFMControl
                ForecastView(result: timesFM.latestForecast ?? demoForecast)
            }
            .padding()
        }
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
                if !timesFM.trace.isEmpty { pipelineCard }
                if let forecast = timesFM.latestForecast { ForecastView(result: forecast) }
                if !result.isEmpty { resultCard }
                suggestionCards
                performanceSection
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            inputCard
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    // Performance moved to the end of the scroll, collapsed by default.
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { showPerformance.toggle() }
            } label: {
                HStack {
                    Label("Performance", systemImage: "speedometer")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: showPerformance ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showPerformance {
                PerformancePanel(
                    metrics: manager.lastMetrics,
                    memoryHistory: manager.memoryHistory,
                    memoryMB: manager.activeMemoryMB + manager.cacheMemoryMB
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
    
    private var canSend: Bool {
        !isGenerating && !prompt.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Ask anything, or tap a forecast…", text: $prompt, axis: .vertical)
                .lineLimit(1...4)
                .focused($promptFocused)

            HStack(spacing: 10) {
                // Reasoning as a subtle toggle chip
                Button { thinkingEnabled.toggle() } label: {
                    Label("Reasoning", systemImage: "brain")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(thinkingEnabled
                                           ? Color.accentColor.opacity(0.18)
                                           : Color.secondary.opacity(0.12))
                        )
                        .foregroundStyle(thinkingEnabled ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                // Circular gradient send button
                Button { submit(prompt) } label: {
                    Group {
                        if isGenerating {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up").font(.headline.weight(.bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(colors: [.blue, .purple],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                    .opacity(canSend ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08)))
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
    
    // MARK: Pipeline trace (makes the LFM → tool → TimesFM orchestration visible)

    private var pipelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PIPELINE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
            ForEach(timesFM.trace) { step in
                HStack(spacing: 10) {
                    Image(systemName: step.icon)
                        .font(.caption)
                        .foregroundStyle(isGenerating && step.id == timesFM.trace.last?.id ? Color.accentColor : .green)
                        .frame(width: 20)
                    Text(step.label).font(.caption)
                    Spacer(minLength: 0)
                    if isGenerating && step.id == timesFM.trace.last?.id {
                        ProgressView().controlSize(.mini)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Suggestions (grouped, glassmorphism grid)

    private struct Suggestion: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let prompt: String
    }
    /// The only prompts we surface are metrics actually wired end-to-end (LFM → TimesFM).
    private var suggestions: [Suggestion] {
        [
            Suggestion(title: "Predict steps", subtitle: "steps/day", icon: "figure.walk",
                       prompt: "Predict my steps for the next 7 days"),
            Suggestion(title: "Predict energy", subtitle: "kcal/day", icon: "flame.fill",
                       prompt: "Predict my active energy for the next 7 days"),
            Suggestion(title: "Predict distance", subtitle: "km/day", icon: "location.fill",
                       prompt: "Predict my walking distance for the next 7 days"),
            Suggestion(title: "Predict photos", subtitle: "photos/day", icon: "photo.on.rectangle.angled",
                       prompt: "Predict my photos for the next 7 days"),
        ]
    }

    private var suggestionCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try Google's TimesFM")
                .font(.title3.bold())
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10),
                          GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(suggestions) { suggestionCard($0) }
            }
            webForecastCard
        }
    }

    /// A shiny, full-width entry point for the web (Wikipedia) forecast.
    private var webForecastCard: some View {
        Button {
            prompt = "Predict interest in "
            promptFocused = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Predict interest in a subject")
                        .font(.subheadline.weight(.semibold))
                    Text("Based on Wikipedia article views + TimesFM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(colors: [.blue, .purple],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }

    private func suggestionCard(_ item: Suggestion) -> some View {
        Button { submit(item.prompt) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: item.icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(item.subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }

    private var languageModelControl: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
                    .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("LFM language agent")
                        .font(.headline)
                    Text("Understands requests and chooses on-device tools")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text("First launch downloads the ~1.5 GB quantized model once and caches it locally.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button {
                Task { await manager.load() }
            } label: {
                modelActionLabel("Download LFM", systemImage: "arrow.down.circle.fill", detail: "~1.5 GB")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
    
    private var timesFMControl: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title3)
                    .foregroundStyle(.purple)
                    .frame(width: 32, height: 32)
                    .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("TimesFM forecast engine")
                        .font(.headline)
                    Text("Runs locally after the first installation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            switch timesFM.state {
            case .idle:
                Text(timesFM.hasCachedWeights
                     ? "Checkpoint is cached locally. Load it into memory to run a forecast."
                     : "First launch downloads the 1.32 GB checkpoint once and stores it on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                
                Button {
                    Task { await timesFM.load() }
                } label: {
                    modelActionLabel(
                        timesFM.hasCachedWeights ? "Load TimesFM" : "Download TimesFM",
                        systemImage: timesFM.hasCachedWeights ? "memorychip.fill" : "arrow.down.circle.fill",
                        detail: timesFM.hasCachedWeights ? "cached" : "1.32 GB"
                    )
                }
                .buttonStyle(.borderedProminent)
                
            case .loading:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Downloading and preparing TimesFM…")
                            .font(.subheadline.weight(.semibold))
                    }
                    
                    Text("This can take several minutes on first launch. Keep the app open and use Wi-Fi when possible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let startedAt = timesFM.loadStartedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("Elapsed \(elapsedTime(since: startedAt, now: context.date))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
            case .ready:
                VStack(alignment: .leading, spacing: 10) {
                    Label("TimesFM is ready on this device", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    
                    Button {
                        Task {
                            await timesFM.forecast(
                                seriesName: demoForecast.seriesName,
                                unit: demoForecast.unit,
                                history: demoForecast.history,
                                horizon: 7
                            )
                        }
                    } label: {
                        modelActionLabel("Run TimesFM forecast", systemImage: "play.fill", detail: "7 days")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(timesFM.isForecasting)
                    
                    if timesFM.isForecasting {
                        ProgressView("Forecasting locally…")
                    }
                    
                    if let error = timesFM.forecastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    if timesFM.latestForecast != nil {
                        Label("Live TimesFM forecast", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                
            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    Label("TimesFM couldn't be prepared", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    
                    Button("Retry download") {
                        Task { await timesFM.retryLoad() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
    
    private func elapsedTime(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    
    private func modelActionLabel(_ title: String, systemImage: String, detail: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(detail)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
}

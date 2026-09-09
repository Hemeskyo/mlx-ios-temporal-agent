//
//  SettingsView.swift
//  mlx-ios-toolcall
//
//  Created by Serhat Akar on 29/08/2026.
//


import SwiftUI
import Charts

struct SettingsView: View {
    @Bindable var manager: ModelManager
    @AppStorage("selectedModel") private var selectedModel: LLMModel = .lfm2Base
    @State private var cachedModels: Set<LLMModel> = []
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    Picker("Model", selection: $selectedModel) {
                        ForEach(LLMModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    if !selectedModel.supportsTools {
                        Text("Chat only — tool calling isn't wired for this model yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Storage") {
                    ForEach(LLMModel.allCases) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName)
                                Text(cachedModels.contains(model) ? "downloaded" : "not downloaded")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if cachedModels.contains(model) {
                                Button(role: .destructive) {
                                    manager.deleteCache(for: model)
                                    cachedModels = manager.cachedModels()
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Section("Sampling") {
                    VStack(alignment: .leading) {
                        Text("Temperature: \(manager.temperature, specifier: "%.2f")")
                        Slider(value: $manager.temperature, in: 0...1.5)
                    }
                    VStack(alignment: .leading) {
                        Text("Top-p: \(manager.topP, specifier: "%.2f")")
                        Slider(value: $manager.topP, in: 0...1)
                    }
                    Stepper("Top-k: \(manager.topK)", value: $manager.topK, in: 0...100, step: 5)
                    Stepper("Max tokens: \(manager.maxTokens)", value: $manager.maxTokens, in: 32...1024, step: 64)
                }
                Section("Device") {
                    LabeledContent("RAM", value: String(format: "%.1f GB", DeviceSpecs.totalRAMGB))
                    LabeledContent("Headroom now", value: "\(DeviceSpecs.availableMB) MB")
                    HStack {
                        Label("\(manager.activeMemoryMB) MB", systemImage: "memorychip")
                        Spacer()
                        Text("cache \(manager.cacheMemoryMB) MB")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.monospacedDigit())
                }
                
                Section("Cache") {
                    Stepper("Limit: \(manager.cacheLimitMB) MB",
                            value: $manager.cacheLimitMB, in: 0...512, step: 16)
                    Button("Use recommended (\(DeviceSpecs.recommendedCacheMB) MB)") {
                        manager.cacheLimitMB = DeviceSpecs.recommendedCacheMB
                    }
                    Toggle("Auto-clear after each run", isOn: $manager.autoClearCache)
                    Button("Clear cache now") { manager.clearCacheNow() }
                }
                
            }
            .navigationTitle("Parameters")
            .onAppear { cachedModels = manager.cachedModels() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

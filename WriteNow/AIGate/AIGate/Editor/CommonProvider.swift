//
//  CommonProvider.swift
//  AIGate
//
//  Created by Lessica on 2024/8/26.
//

import SwiftUI

struct CommonProvider: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let endpoint: String
    let registerURL: URL?
    let defaultModel: String
    let icon: String
    let recommendedModels: [String]
}

extension CommonProvider {
    static let providers: [CommonProvider] = [
        .init(
            name: "OpenAI",
            endpoint: "https://api.openai.com/v1",
            registerURL: URL(string: "https://platform.openai.com/api-keys"),
            defaultModel: "gpt-4o-mini",
            icon: "sparkles",
            recommendedModels: [
                "gpt-4o-mini",
                "gpt-4o",
                "gpt-4.1-mini",
                "gpt-4.1",
            ]
        ),
        .init(
            name: "DeepSeek",
            endpoint: "https://api.deepseek.com",
            registerURL: URL(string: "https://platform.deepseek.com/api_keys"),
            defaultModel: "deepseek-chat",
            icon: "magnifyingglass.circle",
            recommendedModels: [
                "deepseek-chat",
                "deepseek-reasoner",
            ]
        ),
        .init(
            name: "OpenRouter",
            endpoint: "https://openrouter.ai/api/v1",
            registerURL: URL(string: "https://openrouter.ai/keys"),
            defaultModel: "openai/gpt-4o-mini",
            icon: "arrow.triangle.branch",
            recommendedModels: [
                "openai/gpt-4o-mini",
                "anthropic/claude-3.5-sonnet",
                "google/gemini-2.5-flash",
                "deepseek/deepseek-chat",
            ]
        ),
        .init(
            name: "Google Gemini",
            endpoint: "https://generativelanguage.googleapis.com/v1beta/openai",
            registerURL: URL(string: "https://aistudio.google.com/apikey"),
            defaultModel: "gemini-2.5-flash",
            icon: "wand.and.stars",
            recommendedModels: [
                "gemini-2.5-flash",
                "gemini-2.5-pro",
                "gemini-2.0-flash",
            ]
        ),
        .init(
            name: "Groq",
            endpoint: "https://api.groq.com/openai/v1",
            registerURL: URL(string: "https://console.groq.com/keys"),
            defaultModel: "llama-3.3-70b-versatile",
            icon: "bolt.fill",
            recommendedModels: [
                "llama-3.3-70b-versatile",
                "llama-3.1-8b-instant",
                "qwen-qwq-32b",
            ]
        ),
        .init(
            name: "xAI (Grok)",
            endpoint: "https://api.x.ai/v1",
            registerURL: URL(string: "https://console.x.ai"),
            defaultModel: "grok-3-mini",
            icon: "bolt.circle",
            recommendedModels: [
                "grok-3-mini",
                "grok-3",
            ]
        ),
        .init(
            name: "SiliconFlow",
            endpoint: "https://api.siliconflow.cn/v1",
            registerURL: URL(string: "https://cloud.siliconflow.cn/account/ak"),
            defaultModel: "Qwen/Qwen2.5-7B-Instruct",
            icon: "cpu",
            recommendedModels: [
                "Qwen/Qwen2.5-7B-Instruct",
                "Qwen/Qwen2.5-72B-Instruct",
                "deepseek-ai/DeepSeek-V3",
            ]
        ),
        .init(
            name: "Ollama (Local)",
            endpoint: "http://127.0.0.1:11434/v1",
            registerURL: nil,
            defaultModel: "qwen2.5:7b",
            icon: "desktopcomputer",
            recommendedModels: [
                "qwen2.5:7b",
                "llama3.2",
                "gemma3:4b",
            ]
        ),
    ]
}

struct ProviderPickerView: View {
    let onSelect: (CommonProvider) -> Void

    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(CommonProvider.providers) { provider in
                        Button {
                            onSelect(provider)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: provider.icon)
                                    .foregroundColor(.accent)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(provider.endpoint)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if let regURL = provider.registerURL {
                                    Button {
                                        openURL(regURL)
                                    } label: {
                                        Image(systemName: "key.fill")
                                            .font(.footnote)
                                            .padding(6)
                                            .background(Color.accent.opacity(0.12))
                                            .foregroundColor(.accent)
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Common Provider")
                } footer: {
                    Text("Select a preset provider to prefill URL & suggested model, or enter any OpenAI-compatible URL manually.")
                }
            }
            .navigationTitle("Common Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .accentColor(.accent)
        .navigationViewStyle(.stack)
    }
}

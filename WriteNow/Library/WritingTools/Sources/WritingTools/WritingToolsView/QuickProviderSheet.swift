//
//  QuickProviderSheet.swift
//  WritingTools
//

import SwiftUI

private struct QuickCommonProvider: Identifiable {
    var id: String { name }
    let name: String
    let url: String
    let defaultModel: String
    let recommendedModels: [String]
}

private let quickCommonProviders: [QuickCommonProvider] = [
    .init(name: "OpenAI", url: "https://api.openai.com/v1", defaultModel: "gpt-4o-mini", recommendedModels: ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"]),
    .init(name: "DeepSeek", url: "https://api.deepseek.com", defaultModel: "deepseek-chat", recommendedModels: ["deepseek-chat", "deepseek-reasoner"]),
    .init(name: "OpenRouter", url: "https://openrouter.ai/api/v1", defaultModel: "openai/gpt-4o-mini", recommendedModels: ["openai/gpt-4o-mini", "anthropic/claude-3.5-sonnet", "google/gemini-2.5-flash"]),
    .init(name: "Gemini", url: "https://generativelanguage.googleapis.com/v1beta/openai", defaultModel: "gemini-2.5-flash", recommendedModels: ["gemini-2.5-flash", "gemini-2.5-pro"]),
    .init(name: "Groq", url: "https://api.groq.com/openai/v1", defaultModel: "llama-3.3-70b-versatile", recommendedModels: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"]),
    .init(name: "xAI Grok", url: "https://api.x.ai/v1", defaultModel: "grok-3-mini", recommendedModels: ["grok-3-mini", "grok-3"]),
    .init(name: "SiliconFlow", url: "https://api.siliconflow.cn/v1", defaultModel: "Qwen/Qwen2.5-7B-Instruct", recommendedModels: ["Qwen/Qwen2.5-7B-Instruct", "deepseek-ai/DeepSeek-V3"]),
    .init(name: "Ollama", url: "http://127.0.0.1:11434/v1", defaultModel: "qwen2.5:7b", recommendedModels: ["qwen2.5:7b", "llama3.2"]),
]

struct QuickProviderSheet: View {
    @ObservedObject var cfg = Configurator.shared
    @Environment(\.dismiss) var dismiss

    @State private var editingTarget: EndpointItem?
    @State private var isCreatingNew = false

    @State private var name = ""
    @State private var urlText = "https://"
    @State private var token = ""
    @State private var modelID = ""
    @State private var modelsList: [String] = []
    @State private var newModelInput = ""
    @State private var pathMode: EndpointItem.PathMode = .auto
    @State private var useStreaming = true
    @State private var timeoutSeconds = 60
    @State private var revealKey = true

    @State private var fetchedModels: [String] = []
    @State private var modelFilter = ""
    @State private var isFetching = false
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var statusMessage = ""
    @State private var statusIsError = false

    var isFormVisible: Bool {
        isCreatingNew || editingTarget != nil
    }

    var filteredModels: [String] {
        let q = modelFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return fetchedModels }
        return fetchedModels.filter { $0.lowercased().contains(q) }
    }

    private var effectiveActiveModel: String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (modelsList.first ?? "") : trimmed
    }

    var body: some View {
        NavigationView {
            Group {
                if isFormVisible {
                    editorForm
                } else {
                    providerList
                }
            }
            .navigationTitle(isFormVisible ? (isCreatingNew ? "Add Provider" : "Edit Provider") : "Providers & Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isFormVisible {
                        Button("Back") {
                            editingTarget = nil
                            isCreatingNew = false
                            statusMessage = ""
                        }
                    } else {
                        Button("Done") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isFormVisible {
                        Button("Save") { saveForm() }
                            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || effectiveActiveModel.isEmpty || isSaving)
                    } else {
                        Button {
                            beginNew()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            cfg.refreshRuntimeConfig()
        }
    }

    var providerList: some View {
        List {
            if cfg.endpoints.isEmpty {
                Section {
                    Text("No providers configured yet. Tap + to add one directly.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else {
                Section("Saved Providers (Tap to Activate)") {
                    ForEach(cfg.endpoints) { ep in
                        let isActive = ep.id == cfg.activatedEndpointID
                        let models = ep.effectiveModels
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Button {
                                    cfg.switchEndpoint(id: ep.id) { _ in }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isActive ? .accentColor : .secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ep.displayName)
                                                .font(.subheadline.bold())
                                                .foregroundColor(.primary)
                                            Text(ep.model)
                                                .font(.caption)
                                                .foregroundColor(isActive ? .accentColor : .secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    beginEdit(ep)
                                } label: {
                                    Image(systemName: "pencil.circle")
                                        .font(.title3)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.borderless)
                            }

                            if models.count > 1 {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(models, id: \.self) { m in
                                            let selected = isActive && ep.model == m
                                            Button {
                                                cfg.switchEndpoint(id: ep.id, model: m) { _ in }
                                            } label: {
                                                Text(m)
                                                    .font(.system(size: 11, weight: selected ? .semibold : .regular, design: .monospaced))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                                                    .foregroundColor(selected ? .accentColor : .primary)
                                                    .cornerRadius(6)
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                    }
                                    .padding(.leading, 26)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { offsets in
                        for idx in offsets where cfg.endpoints.indices.contains(idx) {
                            cfg.deleteEndpoint(id: cfg.endpoints[idx].id)
                        }
                    }
                }
            }

            Section {
                Button {
                    beginNew()
                } label: {
                    Label("Add New Provider / Model", systemImage: "plus.circle.fill")
                }
            }
        }
    }

    var editorForm: some View {
        Form {
            if isCreatingNew {
                Section("Quick Presets") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickCommonProviders) { p in
                                Button {
                                    if name.isEmpty { name = p.name }
                                    urlText = p.url
                                    if modelID.isEmpty { modelID = p.defaultModel }
                                    modelsList = EndpointItem.normalizeModels(p.recommendedModels, active: modelID)
                                } label: {
                                    Text(p.name)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundColor(.accentColor)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Provider") {
                TextField("Display Name (optional)", text: $name)
                    .disableAutocorrection(true)

                TextField("Base URL (e.g. https://api.openai.com/v1)", text: $urlText)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                HStack {
                    if revealKey {
                        TextField("API Key (optional)", text: $token)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        SecureField("API Key (optional)", text: $token)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    Button {
                        revealKey.toggle()
                    } label: {
                        Image(systemName: revealKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section("Models in this Provider") {
                TextField("Active Model ID (e.g. gpt-4o-mini)", text: $modelID)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                HStack {
                    TextField("Add another model...", text: $newModelInput)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button("Add") {
                        addModel(newModelInput, activate: modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        newModelInput = ""
                    }
                    .disabled(newModelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                ForEach(modelsList, id: \.self) { m in
                    HStack {
                        Button {
                            modelID = m
                        } label: {
                            HStack {
                                Image(systemName: modelID == m ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(modelID == m ? .accentColor : .secondary)
                                Text(m)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        if modelsList.count > 1 {
                            Button {
                                modelsList.removeAll { $0 == m }
                                if modelID == m { modelID = modelsList.first ?? "" }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red.opacity(0.85))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Button {
                    fetchModels()
                } label: {
                    HStack {
                        Label("Fetch Models (Optional)", systemImage: "arrow.clockwise")
                        Spacer()
                        if isFetching { ProgressView() }
                    }
                }
                .disabled(isFetching)
            }

            if !fetchedModels.isEmpty {
                Section("Fetched Models (\(filteredModels.count))") {
                    TextField("Search models...", text: $modelFilter)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    ForEach(filteredModels.prefix(60), id: \.self) { m in
                        let included = modelsList.contains(m) || modelID == m
                        Button {
                            addModel(m, activate: true)
                        } label: {
                            HStack {
                                Text(m)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.primary)
                                Spacer()
                                if modelID == m {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                } else if included {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                } else {
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section("Options & Test") {
                Picker("Path Mode", selection: $pathMode) {
                    ForEach(EndpointItem.PathMode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                Toggle("Streaming (SSE)", isOn: $useStreaming)
                Stepper("Timeout: \(timeoutSeconds)s", value: $timeoutSeconds, in: 15 ... 180, step: 15)

                Button {
                    testConnection()
                } label: {
                    HStack {
                        Label("Test Connection", systemImage: "bolt.horizontal.circle")
                        Spacer()
                        if isTesting { ProgressView() }
                    }
                }
                .disabled(isTesting || effectiveActiveModel.isEmpty)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(statusIsError ? .red : .green)
                }
            }

            Section {
                Button {
                    saveForm()
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save & Activate")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(isSaving || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || effectiveActiveModel.isEmpty)

                if let target = editingTarget {
                    Button(role: .destructive) {
                        cfg.deleteEndpoint(id: target.id) { _ in
                            editingTarget = nil
                            isCreatingNew = false
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Provider")
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func addModel(_ raw: String, activate: Bool) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !modelsList.contains(trimmed) {
            modelsList.append(trimmed)
        }
        if activate {
            modelID = trimmed
        }
    }

    private func beginNew() {
        editingTarget = nil
        isCreatingNew = true
        name = ""
        urlText = "https://"
        token = ""
        modelID = ""
        modelsList = []
        newModelInput = ""
        pathMode = .auto
        useStreaming = true
        timeoutSeconds = cfg.settings.requestTimeout
        revealKey = !cfg.settings.maskEndpointKeys
        fetchedModels = []
        modelFilter = ""
        statusMessage = ""
    }

    private func beginEdit(_ ep: EndpointItem) {
        isCreatingNew = false
        editingTarget = ep
        name = ep.name
        urlText = ep.url.absoluteString
        token = ep.token
        modelID = ep.model
        modelsList = ep.effectiveModels
        newModelInput = ""
        pathMode = ep.pathMode
        useStreaming = ep.useStreaming
        timeoutSeconds = ep.timeoutSeconds
        revealKey = !cfg.settings.maskEndpointKeys
        fetchedModels = []
        modelFilter = ""
        statusMessage = ""
    }

    private func fetchModels() {
        isFetching = true
        statusMessage = ""
        cfg.fetchModelsViaDaemon(
            url: urlText,
            token: token,
            pathMode: pathMode,
            customHeaders: editingTarget?.customHeaders ?? [:]
        ) { result in
            isFetching = false
            switch result {
            case let .success(models):
                fetchedModels = models
                statusIsError = false
                statusMessage = "Loaded \(models.count) models."
                if modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let first = models.first {
                    addModel(first, activate: true)
                }
            case let .failure(err):
                statusIsError = true
                statusMessage = err.localizedDescription
            }
        }
    }

    private func testConnection() {
        isTesting = true
        statusMessage = ""
        cfg.testEndpointViaDaemon(
            url: urlText,
            token: token,
            model: effectiveActiveModel,
            pathMode: pathMode,
            customHeaders: editingTarget?.customHeaders ?? [:],
            timeoutSeconds: timeoutSeconds
        ) { ok, msg in
            isTesting = false
            statusIsError = !ok
            statusMessage = msg
        }
    }

    private func saveForm() {
        isSaving = true
        statusMessage = ""
        let activeModel = effectiveActiveModel
        let allModels = EndpointItem.normalizeModels(modelsList, active: activeModel)
        cfg.upsertEndpoint(
            id: editingTarget?.id,
            name: name,
            url: urlText,
            token: token,
            model: activeModel,
            models: allModels,
            pathMode: pathMode,
            customHeaders: editingTarget?.customHeaders ?? [:],
            useStreaming: useStreaming,
            timeoutSeconds: timeoutSeconds,
            activate: true
        ) { result in
            isSaving = false
            switch result {
            case .success:
                editingTarget = nil
                isCreatingNew = false
            case let .failure(err):
                statusIsError = true
                statusMessage = err.localizedDescription
            }
        }
    }
}

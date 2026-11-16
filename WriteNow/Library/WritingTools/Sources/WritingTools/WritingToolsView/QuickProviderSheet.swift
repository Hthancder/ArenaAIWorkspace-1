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
    let models: [String]
}

private let quickCommonProviders: [QuickCommonProvider] = [
    .init(name: "OpenAI", url: "https://api.openai.com/v1", defaultModel: "gpt-4o-mini", models: ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"]),
    .init(name: "DeepSeek", url: "https://api.deepseek.com", defaultModel: "deepseek-chat", models: ["deepseek-chat", "deepseek-reasoner"]),
    .init(name: "OpenRouter", url: "https://openrouter.ai/api/v1", defaultModel: "openai/gpt-4o-mini", models: ["openai/gpt-4o-mini", "anthropic/claude-3.5-sonnet", "google/gemini-2.5-flash"]),
    .init(name: "Gemini", url: "https://generativelanguage.googleapis.com/v1beta/openai", defaultModel: "gemini-2.5-flash", models: ["gemini-2.5-flash", "gemini-2.5-pro"]),
    .init(name: "Groq", url: "https://api.groq.com/openai/v1", defaultModel: "llama-3.3-70b-versatile", models: ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"]),
    .init(name: "xAI Grok", url: "https://api.x.ai/v1", defaultModel: "grok-3-mini", models: ["grok-3-mini", "grok-3"]),
    .init(name: "SiliconFlow", url: "https://api.siliconflow.cn/v1", defaultModel: "Qwen/Qwen2.5-7B-Instruct", models: ["Qwen/Qwen2.5-7B-Instruct", "deepseek-ai/DeepSeek-V3"]),
    .init(name: "Ollama", url: "http://127.0.0.1:11434/v1", defaultModel: "qwen2.5:7b", models: ["qwen2.5:7b", "llama3.2:latest"]),
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
    @State private var newModelDraft = ""
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

    var effectiveModels: [String] {
        var result: [String] = []
        var seen = Set<String>()
        for m in modelsList {
            let trimmed = m.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        let active = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !active.isEmpty, seen.insert(active).inserted {
            result.insert(active, at: 0)
        }
        return result
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
                            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || effectiveModels.isEmpty || isSaving)
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
                Section("Saved Providers & Models") {
                    ForEach(cfg.endpoints) { ep in
                        let isActive = ep.id == cfg.activatedEndpointID
                        let epModels = ep.normalizedModels
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
                                                .foregroundColor(.secondary)
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

                            if epModels.count > 1 {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(epModels, id: \.self) { m in
                                            let selected = isActive && ep.model == m
                                            Button {
                                                cfg.switchEndpoint(id: ep.id, model: m) { _ in }
                                            } label: {
                                                Text(m)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(selected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12))
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
                                    for m in p.models where !modelsList.contains(m) {
                                        modelsList.append(m)
                                    }
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

            Section("Models in Provider") {
                TextField("Active Model ID (e.g. gpt-4o-mini)", text: $modelID)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                HStack {
                    TextField("Add another model ID...", text: $newModelDraft)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit {
                            addDraftModel()
                        }
                    Button {
                        addDraftModel()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                ForEach(modelsList, id: \.self) { m in
                    let isActive = m == modelID.trimmingCharacters(in: .whitespacesAndNewlines)
                    HStack {
                        Button {
                            modelID = m
                        } label: {
                            HStack {
                                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isActive ? .accentColor : .secondary)
                                Text(m)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            modelsList.removeAll { $0 == m }
                            if modelID == m { modelID = modelsList.first ?? "" }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
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
                        let inList = modelsList.contains(m)
                        Button {
                            if !inList { modelsList.append(m) }
                            modelID = m
                        } label: {
                            HStack {
                                Text(m)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.primary)
                                Spacer()
                                if modelID == m {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                } else if inList {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundColor(.secondary)
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
                        Label("Test Active Model", systemImage: "bolt.horizontal.circle")
                        Spacer()
                        if isTesting { ProgressView() }
                    }
                }
                .disabled(isTesting || effectiveModels.isEmpty)

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
                .disabled(isSaving || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || effectiveModels.isEmpty)

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

    private func addDraftModel() {
        let trimmed = newModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !modelsList.contains(trimmed) {
            modelsList.append(trimmed)
        }
        if modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            modelID = trimmed
        }
        newModelDraft = ""
    }

    private func beginNew() {
        editingTarget = nil
        isCreatingNew = true
        name = ""
        urlText = "https://"
        token = ""
        modelID = ""
        modelsList = []
        newModelDraft = ""
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
        modelsList = ep.normalizedModels
        newModelDraft = ""
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
                    modelID = first
                    if !modelsList.contains(first) { modelsList.append(first) }
                }
            case let .failure(err):
                statusIsError = true
                statusMessage = err.localizedDescription
            }
        }
    }

    private func testConnection() {
        let testModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (effectiveModels.first ?? "")
            : modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !testModel.isEmpty else { return }

        isTesting = true
        statusMessage = ""
        cfg.testEndpointViaDaemon(
            url: urlText,
            token: token,
            model: testModel,
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
        let finalModels = effectiveModels
        guard !finalModels.isEmpty else { return }
        let rawActive = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeModel = rawActive.isEmpty ? finalModels[0] : rawActive

        isSaving = true
        statusMessage = ""
        cfg.upsertEndpoint(
            id: editingTarget?.id,
            name: name,
            url: urlText,
            token: token,
            model: activeModel,
            models: finalModels,
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

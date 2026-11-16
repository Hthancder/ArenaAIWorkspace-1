//
//  AddEndpointView.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/15.
//

import SwiftUI

private struct CustomHeaderRow: Identifiable, Hashable {
    let id = UUID()
    var key: String
    var value: String
}

struct AddEndpointView: View {
    let editingEndpoint: Configuration.Endpoint?

    @StateObject var configuration = Configuration.shared
    @Environment(\.dismiss) var dismiss

    @State private var name: String
    @State private var urlText: String
    @State private var token: String
    @State private var modelID: String
    @State private var modelsList: [String]
    @State private var newModelDraft: String = ""
    @State private var pathMode: Configuration.Endpoint.PathMode
    @State private var useStreaming: Bool
    @State private var timeoutSeconds: Int
    @State private var customHeadersList: [CustomHeaderRow]

    @State private var revealKey: Bool
    @State private var showProviderPicker = false
    @State private var showAdvanced = false

    @State private var fetchedModels: [String] = []
    @State private var modelSearchText = ""
    @State private var isFetchingModels = false
    @State private var fetchStatusMessage = ""
    @State private var fetchErrorMessage = ""

    @State private var isTestingConnection = false
    @State private var testResultMessage = ""
    @State private var testResultOK = false

    @State private var suggestedProviderModels: [String] = []

    init(editingEndpoint: Configuration.Endpoint? = nil) {
        self.editingEndpoint = editingEndpoint
        let initialURL = editingEndpoint?.url.absoluteString ?? Configuration.shared.lastEndpointURL
        let initialToken = editingEndpoint?.token ?? Configuration.shared.lastEndpointKey
        let initialName = editingEndpoint?.name ?? ""
        let initialModel = editingEndpoint?.model ?? ""
        let initialModels = editingEndpoint?.normalizedModels ?? []
        let initialPathMode = editingEndpoint?.pathMode ?? .auto
        let initialStreaming = editingEndpoint?.useStreaming ?? true
        let initialTimeout = editingEndpoint?.timeoutSeconds ?? Configuration.shared.appSettings.requestTimeout
        let initialHeaders = (editingEndpoint?.customHeaders ?? [:]).sorted { $0.key < $1.key }.map {
            CustomHeaderRow(key: $0.key, value: $0.value)
        }

        _name = State(initialValue: initialName)
        _urlText = State(initialValue: initialURL)
        _token = State(initialValue: initialToken)
        _modelID = State(initialValue: initialModel)
        _modelsList = State(initialValue: initialModels)
        _pathMode = State(initialValue: initialPathMode)
        _useStreaming = State(initialValue: initialStreaming)
        _timeoutSeconds = State(initialValue: initialTimeout)
        _customHeadersList = State(initialValue: initialHeaders)
        _revealKey = State(initialValue: !Configuration.shared.appSettings.maskEndpointKeys)
    }

    private var normalizedURL: URL? {
        EndpointURLHelper.normalizeBaseURL(urlText)
    }

    private var resolvedChatPreview: String {
        guard let url = normalizedURL,
              let chatURL = EndpointURLHelper.chatCompletionsURL(baseURL: url, pathMode: pathMode)
        else {
            return "Invalid URL"
        }
        return chatURL.absoluteString
    }

    private var parsedCustomHeaders: [String: String] {
        var dict: [String: String] = [:]
        for item in customHeadersList {
            let k = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !k.isEmpty else { continue }
            dict[k] = item.value
        }
        return dict
    }

    private var filteredModels: [String] {
        let query = modelSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = fetchedModels
        if query.isEmpty { return base }
        return base.filter { $0.lowercased().contains(query) }
    }

    private var effectiveModelsToSave: [String] {
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

    private var canSave: Bool {
        normalizedURL != nil && !effectiveModelsToSave.isEmpty
    }

    var body: some View {
        NavigationView {
            List {
                if editingEndpoint == nil {
                    Section {
                        Button {
                            showProviderPicker = true
                        } label: {
                            HStack {
                                Label("Choose Common Provider", systemImage: "square.grid.2x2")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } footer: {
                        Text("Pick a common provider preset or enter any custom OpenAI-compatible URL below.")
                    }
                }

                Section {
                    HStack {
                        Text("Name")
                            .frame(width: 72, alignment: .leading)
                            .foregroundColor(.secondary)
                        TextField("Optional (e.g. OpenRouter)", text: $name)
                            .disableAutocorrection(true)
                    }

                    HStack {
                        Text("URL")
                            .frame(width: 72, alignment: .leading)
                            .foregroundColor(.secondary)
                        TextField("https://api.openai.com/v1", text: $urlText)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    HStack {
                        Text("Key")
                            .frame(width: 72, alignment: .leading)
                            .foregroundColor(.secondary)
                        if revealKey {
                            TextField("sk-... (optional)", text: $token)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("sk-... (optional)", text: $token)
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
                } header: {
                    Text("Provider")
                } footer: {
                    Text("Chat Endpoint: \(resolvedChatPreview)")
                        .font(.caption2)
                }

                Section {
                    HStack {
                        Text("Active")
                            .frame(width: 72, alignment: .leading)
                            .foregroundColor(.secondary)
                        TextField("e.g. gpt-4o-mini, deepseek-chat", text: $modelID)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        if !modelID.isEmpty {
                            Button {
                                addModelToList(modelID, setActive: true)
                            } label: {
                                Image(systemName: modelsList.contains(modelID.trimmingCharacters(in: .whitespacesAndNewlines)) ? "checkmark.circle.fill" : "plus.circle.fill")
                                    .foregroundColor(.accent)
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    HStack {
                        Text("Add Model")
                            .frame(width: 72, alignment: .leading)
                            .foregroundColor(.secondary)
                        TextField("Add another model ID...", text: $newModelDraft)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onSubmit {
                                commitDraftModel()
                            }
                        Button {
                            commitDraftModel()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(newModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .accent)
                        }
                        .buttonStyle(.borderless)
                        .disabled(newModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !modelsList.isEmpty {
                        ForEach(modelsList, id: \.self) { m in
                            let isActive = (m == modelID.trimmingCharacters(in: .whitespacesAndNewlines))
                            HStack(spacing: 8) {
                                Button {
                                    modelID = m
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isActive ? .accent : .secondary)
                                        Text(m)
                                            .font(.system(.subheadline, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    removeModelFromList(m)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundColor(.red.opacity(0.85))
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    if !suggestedProviderModels.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(suggestedProviderModels, id: \.self) { m in
                                    let inList = modelsList.contains(m)
                                    Button {
                                        toggleModelInList(m)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: inList ? "checkmark" : "plus")
                                                .font(.caption2)
                                            Text(m)
                                                .font(.caption)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(inList ? Color.accent.opacity(0.22) : Color.secondary.opacity(0.12))
                                        .foregroundColor(inList ? .accent : .primary)
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Button {
                        fetchModelsAction()
                    } label: {
                        HStack {
                            Label("Fetch Available Models (Optional)", systemImage: "arrow.clockwise")
                            Spacer()
                            if isFetchingModels {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(normalizedURL == nil || isFetchingModels)

                    if !fetchStatusMessage.isEmpty {
                        Text(fetchStatusMessage)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    if !fetchErrorMessage.isEmpty {
                        Text(fetchErrorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    HStack {
                        Text("Models in Provider")
                        Spacer()
                        if !modelsList.isEmpty {
                            Text("\(modelsList.count) saved")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    Text("Group multiple models under this single provider. Tap a saved model to set it active, or add/fetch more anytime.")
                }

                if !fetchedModels.isEmpty {
                    Section {
                        TextField("Search \(fetchedModels.count) models...", text: $modelSearchText)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        ForEach(filteredModels.prefix(80), id: \.self) { model in
                            let inList = modelsList.contains(model)
                            let isActive = modelID.trimmingCharacters(in: .whitespacesAndNewlines) == model
                            Button {
                                if inList {
                                    modelID = model
                                } else {
                                    addModelToList(model, setActive: true)
                                }
                            } label: {
                                HStack {
                                    Text(model)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if isActive {
                                        Text("Active")
                                            .font(.caption2.bold())
                                            .foregroundColor(.accent)
                                    } else if inList {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accent.opacity(0.75))
                                    } else {
                                        Image(systemName: "plus.circle")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Fetched Models (\(filteredModels.count)) — Tap to Add")
                    }
                }

                Section {
                    Button {
                        testConnectionAction()
                    } label: {
                        HStack {
                            Label("Test Active Model Connection", systemImage: "bolt.horizontal.circle")
                            Spacer()
                            if isTestingConnection {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!canSave || isTestingConnection)

                    if !testResultMessage.isEmpty {
                        Text(testResultMessage)
                            .font(.caption)
                            .foregroundColor(testResultOK ? .green : .red)
                    }

                    DisclosureGroup("Advanced Options", isExpanded: $showAdvanced) {
                        Picker("Path Mode", selection: $pathMode) {
                            ForEach(Configuration.Endpoint.PathMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }

                        Toggle("Enable Streaming (SSE)", isOn: $useStreaming)

                        Stepper("Timeout: \(timeoutSeconds)s", value: $timeoutSeconds, in: 15 ... 180, step: 15)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Custom Headers")
                                    .font(.subheadline)
                                Spacer()
                                Button {
                                    customHeadersList.append(CustomHeaderRow(key: "", value: ""))
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.accent)
                                }
                                .buttonStyle(.borderless)
                            }
                            ForEach($customHeadersList) { $pair in
                                HStack(spacing: 6) {
                                    TextField("Header", text: $pair.key)
                                        .font(.caption)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                    TextField("Value", text: $pair.value)
                                        .font(.caption)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                    Button {
                                        let targetID = pair.id
                                        customHeadersList.removeAll { $0.id == targetID }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Verification & Advanced")
                }

                Section {
                    Button {
                        saveEndpoint()
                    } label: {
                        HStack {
                            Spacer()
                            Text(editingEndpoint == nil ? "Save Provider" : "Update Provider")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .navigationTitle(editingEndpoint == nil ? "Add Provider" : "Edit Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEndpoint() }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showProviderPicker) {
                ProviderPickerView { provider in
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        name = provider.name
                    }
                    urlText = provider.endpoint
                    if modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        modelID = provider.defaultModel
                    }
                    for rec in provider.recommendedModels {
                        addModelToList(rec, setActive: false)
                    }
                    addModelToList(provider.defaultModel, setActive: modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    suggestedProviderModels = provider.recommendedModels
                    fetchErrorMessage = ""
                    fetchStatusMessage = ""
                    testResultMessage = ""
                }
            }
        }
        .accentColor(.accent)
        .navigationViewStyle(.stack)
    }

    private func commitDraftModel() {
        let trimmed = newModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addModelToList(trimmed, setActive: modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        newModelDraft = ""
    }

    private func addModelToList(_ raw: String, setActive: Bool) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !modelsList.contains(trimmed) {
            modelsList.append(trimmed)
        }
        if setActive || modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            modelID = trimmed
        }
    }

    private func toggleModelInList(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if modelsList.contains(trimmed) {
            if modelID != trimmed {
                modelID = trimmed
            } else {
                removeModelFromList(trimmed)
            }
        } else {
            addModelToList(trimmed, setActive: true)
        }
    }

    private func removeModelFromList(_ model: String) {
        modelsList.removeAll { $0 == model }
        if modelID.trimmingCharacters(in: .whitespacesAndNewlines) == model {
            modelID = modelsList.first ?? ""
        }
    }

    private func fetchModelsAction() {
        guard let baseURL = normalizedURL else { return }
        isFetchingModels = true
        fetchErrorMessage = ""
        fetchStatusMessage = ""
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let headers = parsedCustomHeaders

        Task {
            let result = await EndpointNetworkHelper.fetchModels(
                baseURL: baseURL,
                token: trimmedToken,
                pathMode: pathMode,
                customHeaders: headers
            )
            await MainActor.run {
                isFetchingModels = false
                switch result {
                case let .success(models):
                    fetchedModels = models
                    fetchStatusMessage = "Fetched \(models.count) models."
                    if modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let first = models.first {
                        addModelToList(first, setActive: true)
                    }
                case let .failure(error):
                    fetchErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func testConnectionAction() {
        guard let baseURL = normalizedURL else { return }
        let activeToTest = modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (effectiveModelsToSave.first ?? "")
            : modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !activeToTest.isEmpty else { return }

        isTestingConnection = true
        testResultMessage = ""
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let headers = parsedCustomHeaders

        Task {
            let res = await EndpointNetworkHelper.testChatEndpoint(
                baseURL: baseURL,
                token: trimmedToken,
                model: activeToTest,
                pathMode: pathMode,
                customHeaders: headers,
                timeoutSeconds: timeoutSeconds
            )
            await MainActor.run {
                isTestingConnection = false
                testResultOK = res.ok
                testResultMessage = res.message
            }
        }
    }

    private func saveEndpoint() {
        guard let finalURL = normalizedURL else { return }
        let finalModels = effectiveModelsToSave
        guard !finalModels.isEmpty else { return }
        let rawActive = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalModel = rawActive.isEmpty ? finalModels[0] : rawActive
        let finalToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        configuration.lastEndpointURL = finalURL.absoluteString
        configuration.lastEndpointKey = finalToken

        if let existing = editingEndpoint {
            var updated = existing
            updated.name = finalName
            updated.url = finalURL
            updated.token = finalToken
            updated.model = finalModel
            updated.models = finalModels
            updated.pathMode = pathMode
            updated.customHeaders = parsedCustomHeaders
            updated.useStreaming = useStreaming
            updated.timeoutSeconds = timeoutSeconds
            configuration.update(updated)
        } else {
            let newEndpoint = Configuration.Endpoint(
                name: finalName,
                url: finalURL,
                token: finalToken,
                model: finalModel,
                models: finalModels,
                pathMode: pathMode,
                customHeaders: parsedCustomHeaders,
                useStreaming: useStreaming,
                timeoutSeconds: timeoutSeconds
            )
            configuration.add(newEndpoint, activateIfNone: true)
        }
        dismiss()
    }
}

//
//  WriteNowRootView.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/15.
//

import Combine
import MessageUI
import SwiftUI
import SwiftUIIntrospect

private enum EndpointSheetMode: Identifiable {
    case add
    case edit(Configuration.Endpoint)

    var id: String {
        switch self {
        case .add: return "add"
        case let .edit(ep): return "edit-\(ep.id.uuidString)"
        }
    }
}

private enum PresetSheetMode: Identifiable {
    case add
    case edit(Configuration.WritingPreset)

    var id: String {
        switch self {
        case .add: return "add"
        case let .edit(preset): return "edit-\(preset.id.uuidString)"
        }
    }
}

struct WriteNowRootView: View {
    enum ServiceStatus: Equatable {
        case disconnected
        case connecting
        case connected
    }

    let scrollViewSubject: CurrentValueSubject<UIScrollView?, Never>?

    @StateObject var configuration = Configuration.shared
    @StateObject var configurationViewModel = Configuration.shared.viewModel
    @StateObject var appViewModel = WriteNowAppModel.shared

    init(scrollViewSubject: CurrentValueSubject<UIScrollView?, Never>? = nil) {
        self.scrollViewSubject = scrollViewSubject
    }

    @State var serviceStatus: ServiceStatus = .disconnected
    @State private var endpointSheet: EndpointSheetMode?
    @State private var presetSheet: PresetSheetMode?

    @State private var serviceError: String = ""
    @State private var daemonReachable: Bool = true
    @State private var testStatusMessage: String = ""
    @State private var testStatusOK: Bool = false
    @State private var isTestingActive: Bool = false

    @State private var showResetPresetsAlert = false
    @State private var openMailComposer = false
    @State private var mailResult: Result<MFMailComposeResult, Error>? = nil

    @State private var statusTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            serviceSection
            endpointsSection
            presetsSection
            behaviorSection
            testSceneSection
            footerSection
        }
        .animation(.easeInOut(duration: 0.25), value: serviceError)
        .animation(.easeInOut(duration: 0.25), value: configurationViewModel.uiEndpoints)
        .animation(.easeInOut(duration: 0.25), value: configurationViewModel.uiPresets)
        .sheet(item: $endpointSheet) { mode in
            switch mode {
            case .add:
                AddEndpointView(editingEndpoint: nil)
            case let .edit(endpoint):
                AddEndpointView(editingEndpoint: endpoint)
            }
        }
        .sheet(item: $presetSheet) { mode in
            switch mode {
            case .add:
                PresetEditorView(editingPreset: nil)
            case let .edit(preset):
                PresetEditorView(editingPreset: preset)
            }
        }
        .sheet(isPresented: $openMailComposer) {
            MailView(result: $mailResult) { composer in
                composer.setToRecipients(["example@example.com"])
                composer.setSubject("Feedback")
                composer.setMessageBody("Hello, WriteNow!", isHTML: false)
            }
        }
        .alert("Reset All Presets?", isPresented: $showResetPresetsAlert) {
            Button("Reset", role: .destructive) {
                configuration.resetAllPresetsToDefault()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces all custom and modified presets with the 5 built-in presets.")
        }
        .onAppear {
            if Bundle.main.bundleIdentifier == "wiki.qaq.AIGate" {
                _ = GateSessionDelegate()
            }
            configuration.reloadValueFromSystem()
            updateStatus()
        }
        .onReceive(statusTimer) { _ in
            updateStatus()
        }
        .navigationTitle(NSLocalizedString("Write Now", bundle: Bundle.wrti_support, comment: ""))
        .accentColor(.accent)
        .introspect(.list, on: .iOS(.v15)) { tableView in
            scrollViewSubject?.send(tableView)
        }
        .introspect(.list, on: .iOS(.v16, .v17, .v18)) { collectionView in
            scrollViewSubject?.send(collectionView)
        }
    }

    // MARK: - Sections

    var serviceSection: some View {
        Section {
            Toggle(
                NSLocalizedString("Enable Service", bundle: Bundle.wrti_support, comment: ""),
                isOn: $configuration.isEnabled
            )
            .tint(.accent)

            HStack {
                Label("Daemon Status", systemImage: daemonReachable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(daemonReachable ? .green : .orange)
                Spacer()
                Text(daemonReachable ? "Running (127.0.0.1:5540)" : "Not Responding")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let active = configurationViewModel.uiActivatedEndpoint {
                Button {
                    testActiveEndpoint(active)
                } label: {
                    HStack {
                        Label("Test Active Endpoint", systemImage: "bolt.horizontal.circle")
                        Spacer()
                        if isTestingActive {
                            ProgressView()
                        } else {
                            Text(active.displayModel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .disabled(isTestingActive)

                if !testStatusMessage.isEmpty {
                    Text(testStatusMessage)
                        .font(.caption)
                        .foregroundColor(testStatusOK ? .green : .red)
                }
            }

            if !serviceError.isEmpty {
                Text(serviceError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(NSLocalizedString("Service", bundle: Bundle.wrti_support, comment: ""))
        } footer: {
            Text(NSLocalizedString(
                "Your configuration will be stored securely and will not be accessible to apps. This service will delegate your request from tweaks to server and sending response back to them.",
                bundle: Bundle.wrti_support,
                comment: ""
            ))
        }
    }

    var endpointsSection: some View {
        Section {
            ForEach(configurationViewModel.uiEndpoints) { ep in
                EndpointButton(endpoint: ep) {
                    endpointSheet = .edit(ep)
                }
            }
            .onDelete { offsets in
                let current = configurationViewModel.uiEndpoints
                for idx in offsets where current.indices.contains(idx) {
                    configuration.remove(current[idx])
                }
            }

            Button {
                endpointSheet = .add
            } label: {
                Label(NSLocalizedString("Add Endpoint", bundle: Bundle.wrti_support, comment: ""), systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Text(NSLocalizedString("Endpoints", bundle: Bundle.wrti_support, comment: ""))
                Spacer()
                if !configurationViewModel.uiEndpoints.isEmpty {
                    Text("\(configurationViewModel.uiEndpoints.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } footer: {
            Text("Tap an endpoint to activate it. Tap the slider icon or long press to edit, test, duplicate, or delete. No model fetching is required to save.")
        }
    }

    var presetsSection: some View {
        Section {
            ForEach(configurationViewModel.uiPresets) { preset in
                HStack(spacing: 10) {
                    Button {
                        presetSheet = .edit(preset)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: preset.icon)
                                .foregroundColor(preset.isEnabled ? .accent : .secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(preset.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(preset.isEnabled ? .primary : .secondary)
                                    if !preset.outputLanguage.isEmpty {
                                        Text(preset.outputLanguage)
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.accent.opacity(0.14))
                                            .foregroundColor(.accent)
                                            .cornerRadius(4)
                                    }
                                    if preset.insertBehavior == .append {
                                        Text("Append")
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.14))
                                            .foregroundColor(.secondary)
                                            .cornerRadius(4)
                                    }
                                }
                                Text(preset.systemPrompt)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Toggle("", isOn: Binding(
                        get: { preset.isEnabled },
                        set: { newVal in
                            var updated = preset
                            updated.isEnabled = newVal
                            configuration.updatePreset(updated)
                        }
                    ))
                    .labelsHidden()
                    .tint(.accent)
                }
            }
            .onDelete { offsets in
                let list = configurationViewModel.uiPresets
                for idx in offsets where list.indices.contains(idx) {
                    configuration.deletePreset(id: list[idx].id)
                }
            }
            .onMove { source, destination in
                configuration.movePresets(from: source, to: destination)
            }

            Button {
                presetSheet = .add
            } label: {
                Label("Add Custom Preset", systemImage: "plus.circle.fill")
            }

            Button {
                configuration.restoreMissingDefaultPresets()
            } label: {
                Label("Restore Default Presets", systemImage: "arrow.uturn.backward.circle")
            }

            Button(role: .destructive) {
                showResetPresetsAlert = true
            } label: {
                Label("Reset All Presets to Default", systemImage: "trash.circle")
            }
        } header: {
            HStack {
                Text("Writing Presets")
                Spacer()
                EditButton()
                    .font(.caption)
            }
        } footer: {
            Text("Edit, reorder, hide, or delete any preset (including defaults). Use Restore Default Presets anytime to recover missing defaults.")
        }
    }

    var behaviorSection: some View {
        Section {
            NavigationLink {
                BehaviorSettingsView()
            } label: {
                HStack {
                    Label("Behavior, Appearance & Backup", systemImage: "gearshape.2.fill")
                    Spacer()
                    Text("\(configurationViewModel.uiSettings.gridColumns) cols · \(configurationViewModel.uiSettings.requestTimeout)s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Customization")
        }
    }

    var testSceneSection: some View {
        Section {
            NavigationLink {
                TestTextView()
            } label: {
                Label(NSLocalizedString("Test Text Editor", bundle: Bundle.wrti_support, comment: ""), systemImage: "square.and.pencil")
            }

            if MFMailComposeViewController.canSendMail() {
                Button {
                    openMailComposer = true
                } label: {
                    Label(NSLocalizedString("Test Mail Composer", bundle: Bundle.wrti_support, comment: ""), systemImage: "envelope")
                }
            }
        } header: {
            Text(NSLocalizedString("Test Scene", bundle: Bundle.wrti_support, comment: ""))
        }
    }

    var footerSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text("WriteNow RootHide · \(Bundle.wrti_packageVersion)")
        }
    }

    // MARK: - Actions

    private func testActiveEndpoint(_ endpoint: Configuration.Endpoint) {
        isTestingActive = true
        testStatusMessage = ""
        Task {
            let res = await EndpointNetworkHelper.testChatEndpoint(
                baseURL: endpoint.url,
                token: endpoint.token,
                model: endpoint.model,
                pathMode: endpoint.pathMode,
                customHeaders: endpoint.customHeaders,
                timeoutSeconds: endpoint.timeoutSeconds
            )
            await MainActor.run {
                isTestingActive = false
                testStatusOK = res.ok
                testStatusMessage = res.message
            }
        }
    }

    private func updateStatus() {
        var comps = URLComponents(url: AIGateConfiguration.listenURL, resolvingAgainstBaseURL: false)!
        comps.path = "/metrics"
        comps.queryItems = [URLQueryItem(name: "query", value: "status")]
        guard let url = comps.url else { return }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 2)
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if error != nil || data == nil {
                    self.daemonReachable = false
                    self.serviceStatus = .disconnected
                    return
                }
                self.daemonReachable = true
                self.serviceStatus = .connected
                if let data,
                   let decoded = try? JSONDecoder().decode([String: String].self, from: data)
                {
                    self.serviceError = decoded["error"] ?? ""
                }
            }
        }.resume()
    }
}

// MARK: - Preset Editor Sheet

struct PresetEditorView: View {
    let editingPreset: Configuration.WritingPreset?

    @StateObject var configuration = Configuration.shared
    @Environment(\.dismiss) var dismiss

    @State private var title: String
    @State private var icon: String
    @State private var systemPrompt: String
    @State private var temperature: Double
    @State private var includeExamples: Bool
    @State private var outputLanguage: String
    @State private var insertBehavior: Configuration.WritingPreset.InsertBehavior
    @State private var isEnabled: Bool
    @State private var showIconGrid = false

    private let iconOptions: [String] = [
        "sparkles", "wand.and.stars", "doc.text.magnifyingglass", "arrow.counterclockwise",
        "bubble.left.and.bubble.right", "books.vertical", "textformat.abc.dottedunderline",
        "globe", "character.book.closed", "list.bullet", "text.alignleft", "text.quote",
        "pencil.and.outline", "bolt.fill", "lightbulb", "checkmark.seal", "doc.plaintext",
        "envelope", "terminal", "chevron.left.forwardslash.chevron.right", "flame",
        "heart", "star", "flag", "scissors", "arrow.up.right.square", "brain.head.profile",
        "paperplane", "eyeglasses", "graduationcap", "briefcase", "hammer",
    ]

    private let languageSuggestions = ["", "English", "Tiếng Việt", "中文", "日本語", "한국어", "Français"]

    init(editingPreset: Configuration.WritingPreset?) {
        self.editingPreset = editingPreset
        _title = State(initialValue: editingPreset?.title ?? "")
        _icon = State(initialValue: editingPreset?.icon ?? "sparkles")
        _systemPrompt = State(initialValue: editingPreset?.systemPrompt ?? "")
        _temperature = State(initialValue: editingPreset?.temperature ?? 0.3)
        _includeExamples = State(initialValue: editingPreset?.includeExamples ?? false)
        _outputLanguage = State(initialValue: editingPreset?.outputLanguage ?? "")
        _insertBehavior = State(initialValue: editingPreset?.insertBehavior ?? .replace)
        _isEnabled = State(initialValue: editingPreset?.isEnabled ?? true)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 12) {
                        Button {
                            showIconGrid.toggle()
                        } label: {
                            Image(systemName: icon.isEmpty ? "sparkles" : icon)
                                .font(.title3)
                                .foregroundColor(.accent)
                                .frame(width: 40, height: 40)
                                .background(Color.accent.opacity(0.14))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.borderless)

                        TextField("Preset Title (e.g. Translate VN)", text: $title)
                    }

                    HStack {
                        Text("SF Symbol")
                            .foregroundColor(.secondary)
                        TextField("sparkles", text: $icon)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        Button(showIconGrid ? "Hide Icons" : "Pick Icon") {
                            showIconGrid.toggle()
                        }
                        .font(.caption)
                    }

                    if showIconGrid {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                            ForEach(iconOptions, id: \.self) { sym in
                                Button {
                                    icon = sym
                                    showIconGrid = false
                                } label: {
                                    Image(systemName: sym)
                                        .font(.body)
                                        .frame(width: 36, height: 36)
                                        .background(icon == sym ? Color.accent.opacity(0.25) : Color.secondary.opacity(0.1))
                                        .foregroundColor(icon == sym ? .accent : .primary)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("Identity")
                }

                Section {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 130)
                        .font(.body)
                } header: {
                    Text("System Prompt")
                } footer: {
                    Text("Instructions sent to the AI model when you tap this preset.")
                }

                Section {
                    HStack {
                        Text("Output Language")
                        Spacer()
                        TextField("Auto", text: $outputLanguage)
                            .multilineTextAlignment(.trailing)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(languageSuggestions, id: \.self) { lang in
                                Button {
                                    outputLanguage = lang
                                } label: {
                                    Text(lang.isEmpty ? "Auto" : lang)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(outputLanguage == lang ? Color.accent.opacity(0.2) : Color.secondary.opacity(0.12))
                                        .foregroundColor(outputLanguage == lang ? .accent : .primary)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Picker("Insert Behavior", selection: $insertBehavior) {
                        Text("Replace Selection").tag(Configuration.WritingPreset.InsertBehavior.replace)
                        Text("Append After Selection").tag(Configuration.WritingPreset.InsertBehavior.append)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.2f", temperature))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $temperature, in: 0.0 ... 1.2, step: 0.05)
                            .tint(.accent)
                    }

                    Toggle("Include Few-shot Examples", isOn: $includeExamples)
                        .tint(.accent)

                    Toggle("Enabled in Menu", isOn: $isEnabled)
                        .tint(.accent)
                } header: {
                    Text("Execution Options")
                }

                Section {
                    Button {
                        save()
                    } label: {
                        HStack {
                            Spacer()
                            Text(editingPreset == nil ? "Add Preset" : "Save Preset")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .navigationTitle(editingPreset == nil ? "New Preset" : "Edit Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .accentColor(.accent)
        .navigationViewStyle(.stack)
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLang = outputLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanPrompt.isEmpty else { return }

        if var existing = editingPreset {
            existing.title = cleanTitle
            existing.icon = cleanIcon.isEmpty ? "sparkles" : cleanIcon
            existing.systemPrompt = cleanPrompt
            existing.temperature = temperature
            existing.includeExamples = includeExamples
            existing.outputLanguage = cleanLang
            existing.insertBehavior = insertBehavior
            existing.isEnabled = isEnabled
            configuration.updatePreset(existing)
        } else {
            let preset = Configuration.WritingPreset(
                defaultKey: nil,
                title: cleanTitle,
                icon: cleanIcon.isEmpty ? "sparkles" : cleanIcon,
                systemPrompt: cleanPrompt,
                temperature: temperature,
                topP: nil,
                includeExamples: includeExamples,
                outputLanguage: cleanLang,
                insertBehavior: insertBehavior,
                isEnabled: isEnabled
            )
            configuration.addPreset(preset)
        }
        dismiss()
    }
}

// MARK: - Behavior, Appearance & Backup View

struct BehaviorSettingsView: View {
    @StateObject var configuration = Configuration.shared
    @StateObject var viewModel = Configuration.shared.viewModel

    @State private var menuTitle: String
    @State private var globalPrompt: String
    @State private var useFewShot: Bool
    @State private var stripThink: Bool
    @State private var streaming: Bool
    @State private var autoSelectAll: Bool
    @State private var unmaskKeys: Bool
    @State private var timeout: Int
    @State private var gridColumns: Int
    @State private var sizePreset: String
    @State private var animatedBg: Bool

    @State private var backupAlertTitle = ""
    @State private var backupAlertMessage = ""
    @State private var showBackupAlert = false

    init() {
        let s = Configuration.shared.appSettings
        _menuTitle = State(initialValue: s.menuTitle)
        _globalPrompt = State(initialValue: s.globalSystemPrompt)
        _useFewShot = State(initialValue: s.useFewShotExamples)
        _stripThink = State(initialValue: s.stripThinkingTags)
        _streaming = State(initialValue: s.streamingEnabled)
        _autoSelectAll = State(initialValue: s.autoSelectAllIfEmpty)
        _unmaskKeys = State(initialValue: !s.maskEndpointKeys)
        _timeout = State(initialValue: s.requestTimeout)
        _gridColumns = State(initialValue: s.gridColumns)
        _sizePreset = State(initialValue: s.popoverSizePreset)
        _animatedBg = State(initialValue: s.animatedBackground)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Menu Button Title")
                    Spacer()
                    TextField("Write Now", text: $menuTitle)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Text Selection Menu")
            } footer: {
                Text("Title shown in the iOS text selection menu (e.g. Write Now, AI).")
            }

            Section {
                TextEditor(text: $globalPrompt)
                    .frame(minHeight: 90)
                    .font(.body)
            } header: {
                Text("Global System Instructions")
            } footer: {
                Text("Optional instructions appended to every prompt and preset.")
            }

            Section {
                Toggle("Unmask Endpoint Keys", isOn: $unmaskKeys)
                Toggle("Enable Streaming (SSE)", isOn: $streaming)
                Toggle("Strip <think> Reasoning Tags", isOn: $stripThink)
                Toggle("Include Few-shot Examples", isOn: $useFewShot)
                Toggle("Auto-select All When Selection Empty", isOn: $autoSelectAll)
                Stepper("Request Timeout: \(timeout)s", value: $timeout, in: 15 ... 180, step: 15)
            } header: {
                Text("AI Behavior & Security")
            }

            Section {
                Picker("Preset Grid Columns", selection: $gridColumns) {
                    Text("2 Columns").tag(2)
                    Text("3 Columns").tag(3)
                }
                Picker("Popover Size", selection: $sizePreset) {
                    Text("Compact").tag("compact")
                    Text("Standard").tag("standard")
                    Text("Large").tag("large")
                }
                Toggle("Animated Mesh Background", isOn: $animatedBg)
            } header: {
                Text("Popover Appearance (iPhone 7 Plus)")
            } footer: {
                Text("Disable Animated Background or choose Compact size for extra smoothness on iOS 15.")
            }

            Section {
                Button {
                    if let data = configuration.exportBackupJSON(),
                       let str = String(data: data, encoding: .utf8)
                    {
                        UIPasteboard.general.string = str
                        backupAlertTitle = "Exported"
                        backupAlertMessage = "Full configuration JSON (endpoints, presets, settings) copied to clipboard."
                    } else {
                        backupAlertTitle = "Export Failed"
                        backupAlertMessage = "Could not serialize configuration."
                    }
                    showBackupAlert = true
                } label: {
                    Label("Export Backup JSON to Clipboard", systemImage: "square.and.arrow.up")
                }

                Button {
                    guard let raw = UIPasteboard.general.string,
                          let data = raw.data(using: .utf8)
                    else {
                        backupAlertTitle = "Clipboard Empty"
                        backupAlertMessage = "Copy a valid WriteNow JSON backup to clipboard first."
                        showBackupAlert = true
                        return
                    }
                    do {
                        try configuration.importBackupJSON(data)
                        syncFromSettings(configuration.appSettings)
                        backupAlertTitle = "Imported"
                        backupAlertMessage = "Backup restored successfully."
                    } catch {
                        backupAlertTitle = "Import Failed"
                        backupAlertMessage = error.localizedDescription
                    }
                    showBackupAlert = true
                } label: {
                    Label("Import Backup JSON from Clipboard", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Backup & Restore")
            }
        }
        .tint(.accent)
        .navigationTitle("Customization")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: menuTitle) { _ in commitSettings() }
        .onChange(of: globalPrompt) { _ in commitSettings() }
        .onChange(of: useFewShot) { _ in commitSettings() }
        .onChange(of: stripThink) { _ in commitSettings() }
        .onChange(of: streaming) { _ in commitSettings() }
        .onChange(of: autoSelectAll) { _ in commitSettings() }
        .onChange(of: unmaskKeys) { _ in commitSettings() }
        .onChange(of: timeout) { _ in commitSettings() }
        .onChange(of: gridColumns) { _ in commitSettings() }
        .onChange(of: sizePreset) { _ in commitSettings() }
        .onChange(of: animatedBg) { _ in commitSettings() }
        .alert(backupAlertTitle, isPresented: $showBackupAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupAlertMessage)
        }
    }

    private func commitSettings() {
        configuration.updateSettings { s in
            let cleanedTitle = menuTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            s.menuTitle = cleanedTitle.isEmpty ? "Write Now" : cleanedTitle
            s.globalSystemPrompt = globalPrompt
            s.useFewShotExamples = useFewShot
            s.stripThinkingTags = stripThink
            s.streamingEnabled = streaming
            s.autoSelectAllIfEmpty = autoSelectAll
            s.maskEndpointKeys = !unmaskKeys
            s.requestTimeout = timeout
            s.gridColumns = gridColumns
            s.popoverSizePreset = sizePreset
            s.animatedBackground = animatedBg
        }
    }

    private func syncFromSettings(_ s: Configuration.AppSettings) {
        menuTitle = s.menuTitle
        globalPrompt = s.globalSystemPrompt
        useFewShot = s.useFewShotExamples
        stripThink = s.stripThinkingTags
        streaming = s.streamingEnabled
        autoSelectAll = s.autoSelectAllIfEmpty
        unmaskKeys = !s.maskEndpointKeys
        timeout = s.requestTimeout
        gridColumns = s.gridColumns
        sizePreset = s.popoverSizePreset
        animatedBg = s.animatedBackground
    }
}

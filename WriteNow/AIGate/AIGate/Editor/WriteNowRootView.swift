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
import UIKit

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
    @State private var mergeNoticeMessage: String = ""

    @State private var showResetPresetsAlert = false
    @State private var openMailComposer = false
    @State private var mailResult: Result<MFMailComposeResult, Error>? = nil

    @State private var statusTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var activeAccent: Color {
        configurationViewModel.uiAccentColor
    }

    var body: some View {
        List {
            creditBannerSection
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
        .accentColor(activeAccent)
        .tint(activeAccent)
        .introspect(.list, on: .iOS(.v15)) { tableView in
            scrollViewSubject?.send(tableView)
        }
        .introspect(.list, on: .iOS(.v16, .v17, .v18)) { collectionView in
            scrollViewSubject?.send(collectionView)
        }
    }

    // MARK: - Sections

    var creditBannerSection: some View {
        Section {
            CreditHeroCard(accentColor: activeAccent)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
        }
    }

    var serviceSection: some View {
        Section {
            Toggle(
                NSLocalizedString("Enable Service", bundle: Bundle.wrti_support, comment: ""),
                isOn: $configuration.isEnabled
            )
            .tint(activeAccent)

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

            if configuration.hasDuplicateProviderGroups {
                Button {
                    let count = configuration.mergeDuplicateProviders()
                    mergeNoticeMessage = count > 0
                        ? "Merged \(count) duplicate endpoint(s) into grouped providers."
                        : "All providers are already grouped."
                } label: {
                    Label("Merge Same-Provider Models", systemImage: "rectangle.stack.badge.plus")
                        .foregroundColor(activeAccent)
                }
            }

            if !mergeNoticeMessage.isEmpty {
                Text(mergeNoticeMessage)
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Button {
                endpointSheet = .add
            } label: {
                Label(NSLocalizedString("Add Provider / Endpoint", bundle: Bundle.wrti_support, comment: ""), systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Text("Providers & Models")
                Spacer()
                if !configurationViewModel.uiEndpoints.isEmpty {
                    Text("\(configurationViewModel.uiEndpoints.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } footer: {
            Text("Each provider holds multiple models. Tap a model pill to switch models in 1 tap, or tap the slider icon to add/manage models inside a provider.")
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
                                .foregroundColor(preset.isEnabled ? activeAccent : .secondary)
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
                                            .background(activeAccent.opacity(0.14))
                                            .foregroundColor(activeAccent)
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
                    .tint(activeAccent)
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
                    Label("Themes, Text FX, Behavior & Backup", systemImage: "paintbrush.pointed.fill")
                    Spacer()
                    Text("\(configurationViewModel.uiSettings.menuThemePreset) · \(configurationViewModel.uiSettings.textAnimationStyle)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        } header: {
            Text("Customization & Themes")
        } footer: {
            Text("Customize WriteNow menu background image, color themes, accent color picker, and text replace animations (Shatter, Fall, Ash Dust, Wave, Glitch, Typewriter).")
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
            Text("WriteNow RootHide · \(Bundle.wrti_packageVersion) · Credit to Hthan24 & owngoal-dev")
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

// MARK: - Impressive Animated Credit Hero Card

struct CreditHeroCard: View {
    let accentColor: Color

    @State private var animateGradient = false
    @State private var shimmerOffset: CGFloat = -1.3
    @State private var pulseRing = false
    @State private var tapBurst = false

    var body: some View {
        ZStack {
            // Animated flowing aurora backdrop
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: animateGradient
                            ? [
                                Color(red: 0.08, green: 0.14, blue: 0.34),
                                accentColor.opacity(0.85),
                                Color(red: 0.38, green: 0.16, blue: 0.62),
                                Color(red: 0.06, green: 0.24, blue: 0.36),
                            ]
                            : [
                                Color(red: 0.14, green: 0.10, blue: 0.34),
                                Color(red: 0.06, green: 0.32, blue: 0.56),
                                accentColor.opacity(0.80),
                                Color(red: 0.10, green: 0.16, blue: 0.30),
                            ],
                        startPoint: animateGradient ? .topLeading : .bottomLeading,
                        endPoint: animateGradient ? .bottomTrailing : .topTrailing
                    )
                )

            // Ambient glowing orbs
            Circle()
                .fill(accentColor.opacity(0.45))
                .frame(width: 140, height: 140)
                .blur(radius: 26)
                .offset(x: animateGradient ? -90 : 80, y: animateGradient ? -35 : 30)

            Circle()
                .fill(Color.cyan.opacity(0.35))
                .frame(width: 110, height: 110)
                .blur(radius: 24)
                .offset(x: animateGradient ? 95 : -80, y: animateGradient ? 30 : -30)

            // Diagonal sweeping light shimmer
            GeometryReader { geo in
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geo.size.width * 0.45)
                .rotationEffect(.degrees(24))
                .offset(x: shimmerOffset * geo.size.width * 1.4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            // Main content
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [.cyan, accentColor, .purple, .yellow, .cyan],
                                    center: .center
                                ),
                                lineWidth: 2.5
                            )
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(animateGradient ? 360 : 0))

                        Circle()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 36, height: 36)

                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(pulseRing ? 1.15 : 0.92)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("WRITENOW ENHANCED EDITION")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1.6)
                            .foregroundColor(.white.opacity(0.78))

                        Text("Credit to Hthan24 for improve")
                            .font(.system(size: 19, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                            .minimumScaleFactor(0.75)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }

                Text("and for owngoal-dev for nice opensource project !")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(10)

                HStack(spacing: 8) {
                    Label("Multi-Model Providers", systemImage: "cpu")
                    Spacer()
                    Label("Custom Themes & Text FX", systemImage: "wand.and.stars")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
            }
            .padding(16)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            accentColor.opacity(0.75),
                            Color.cyan.opacity(0.55),
                        ],
                        startPoint: animateGradient ? .topLeading : .bottomTrailing,
                        endPoint: animateGradient ? .bottomTrailing : .topLeading
                    ),
                    lineWidth: 1.5
                )
        )
        .scaleEffect(tapBurst ? 0.97 : 1.0)
        .shadow(color: accentColor.opacity(0.35), radius: 12, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) {
                tapBurst = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                    tapBurst = false
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                pulseRing = true
            }
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                shimmerOffset = 1.4
            }
        }
    }
}

// MARK: - Preset Editor Sheet

struct PresetEditorView: View {
    let editingPreset: Configuration.WritingPreset?

    @StateObject var configuration = Configuration.shared
    @StateObject var viewModel = Configuration.shared.viewModel
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
                                .foregroundColor(viewModel.uiAccentColor)
                                .frame(width: 40, height: 40)
                                .background(viewModel.uiAccentColor.opacity(0.14))
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
                                        .background(icon == sym ? viewModel.uiAccentColor.opacity(0.25) : Color.secondary.opacity(0.1))
                                        .foregroundColor(icon == sym ? viewModel.uiAccentColor : .primary)
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
                                        .background(outputLanguage == lang ? viewModel.uiAccentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                                        .foregroundColor(outputLanguage == lang ? viewModel.uiAccentColor : .primary)
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
                            .tint(viewModel.uiAccentColor)
                    }

                    Toggle("Include Few-shot Examples", isOn: $includeExamples)
                        .tint(viewModel.uiAccentColor)

                    Toggle("Enabled in Menu", isOn: $isEnabled)
                        .tint(viewModel.uiAccentColor)
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
        .accentColor(viewModel.uiAccentColor)
        .tint(viewModel.uiAccentColor)
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

// MARK: - Behavior, Theme, Text FX & Backup View

private struct ThemePresetOption: Identifiable {
    let id: String
    let title: String
    let colors: [Color]
}

private let menuThemeOptions: [ThemePresetOption] = [
    .init(id: "appleIntelligence", title: "Apple Intelligence", colors: [.purple, .pink, .orange, .blue]),
    .init(id: "midnightBlue", title: "Midnight Ocean", colors: [Color(hexString: "#0F172A"), Color(hexString: "#1D4ED8"), Color(hexString: "#06B6D4")]),
    .init(id: "emeraldForest", title: "Emerald Forest", colors: [Color(hexString: "#064E3B"), Color(hexString: "#10B981"), Color(hexString: "#14B8A6")]),
    .init(id: "sunsetAmber", title: "Sunset Amber", colors: [Color(hexString: "#7C2D12"), Color(hexString: "#F97316"), Color(hexString: "#EAB308")]),
    .init(id: "obsidianMono", title: "Obsidian Dark", colors: [Color(hexString: "#09090B"), Color(hexString: "#27272A"), Color(hexString: "#52525B")]),
    .init(id: "sakuraBlossom", title: "Sakura Rose", colors: [Color(hexString: "#4C0519"), Color(hexString: "#EC4899"), Color(hexString: "#A855F7")]),
    .init(id: "cyberNeon", title: "Cyber Neon", colors: [Color(hexString: "#312E81"), Color(hexString: "#06B6D4"), Color(hexString: "#22C55E")]),
    .init(id: "customColor", title: "Custom Colors", colors: [.blue, .indigo]),
    .init(id: "customImage", title: "Custom Photo", colors: [.gray, .black]),
]

private let animationStyleOptions: [(id: String, title: String, subtitle: String)] = [
    ("shatter", "Shatter & Assemble", "Old text shatters into fragments across screen, new text flies in"),
    ("fallDown", "Gravity Fall & Rise", "Old text drops down with gravity, new text rises up"),
    ("ashDust", "Ash & Dust (Snap)", "Old text dissolves into glowing ash dust particles, new text grows"),
    ("wave", "Wave Flip", "Ripple wave flips old text away and reveals new text"),
    ("glitch", "Cyber Glitch", "RGB digital glitch scramble before locking new text"),
    ("typewriter", "Laser Typewriter", "Laser sweep erases old text and types new text smoothly"),
    ("magicGlow", "Apple Magic Glow", "Luminous rainbow sweep across the selection"),
    ("none", "Instant (No Animation)", "Replace text immediately"),
]

private let accentSwatchColors: [(name: String, hex: String)] = [
    ("Ocean", "#3B82F6"),
    ("Emerald", "#10B981"),
    ("Violet", "#8B5CF6"),
    ("Amber", "#F59E0B"),
    ("Crimson", "#EF4444"),
    ("Cyan", "#06B6D4"),
    ("Rose", "#EC4899"),
    ("Graphite", "#64748B"),
]

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

    @State private var textAnimationStyle: String
    @State private var menuThemePreset: String
    @State private var customColor1: Color
    @State private var customColor2: Color
    @State private var bgBlur: Double
    @State private var bgDim: Double
    @State private var accentColor: Color

    @State private var previewBgImage: UIImage?
    @State private var showPhotoPicker = false

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
        _textAnimationStyle = State(initialValue: s.textAnimationStyle)
        _menuThemePreset = State(initialValue: s.menuThemePreset)
        _customColor1 = State(initialValue: Color(hexString: s.menuCustomColorHex1, fallback: .blue))
        _customColor2 = State(initialValue: Color(hexString: s.menuCustomColorHex2, fallback: .indigo))
        _bgBlur = State(initialValue: s.menuBgImageBlur)
        _bgDim = State(initialValue: s.menuBgImageDim)
        _accentColor = State(initialValue: Color(hexString: s.accentColorHex, fallback: .blue))
        if let data = GlobalStorage.shared.loadMenuBackgroundImage(), let img = UIImage(data: data) {
            _previewBgImage = State(initialValue: img)
        } else {
            _previewBgImage = State(initialValue: nil)
        }
    }

    var body: some View {
        List {
            // Accent Color Theme (Settings & Controls)
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(accentSwatchColors, id: \.hex) { swatch in
                            let c = Color(hexString: swatch.hex)
                            Button {
                                accentColor = c
                            } label: {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(c)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary, lineWidth: accentColor.hexRGBString == swatch.hex ? 2.5 : 0)
                                                .padding(-3)
                                        )
                                    Text(swatch.name)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 6)
                }

                ColorPicker("Custom Accent Color", selection: $accentColor, supportsOpacity: false)
            } header: {
                Text("App Accent Color")
            } footer: {
                Text("Replace the default pink accent with any preset or custom color from the color wheel.")
            }

            // WriteNow Menu Theme & Background Image
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(menuThemeOptions) { option in
                            let selected = menuThemePreset == option.id
                            Button {
                                menuThemePreset = option.id
                            } label: {
                                VStack(spacing: 5) {
                                    ZStack {
                                        if option.id == "customImage", let previewBgImage {
                                            Image(uiImage: previewBgImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 56, height: 42)
                                                .clipped()
                                        } else if option.id == "customColor" {
                                            LinearGradient(colors: [customColor1, customColor2], startPoint: .topLeading, endPoint: .bottomTrailing)
                                                .frame(width: 56, height: 42)
                                        } else {
                                            LinearGradient(colors: option.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                                .frame(width: 56, height: 42)
                                        }

                                        if option.id == "customImage" && previewBgImage == nil {
                                            Image(systemName: "photo")
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selected ? accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2.5 : 1)
                                    )

                                    Text(option.title)
                                        .font(.system(size: 10, weight: selected ? .bold : .regular))
                                        .foregroundColor(selected ? accentColor : .primary)
                                        .lineLimit(1)
                                }
                                .frame(width: 68)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if menuThemePreset == "customColor" {
                    ColorPicker("Background Color 1", selection: $customColor1, supportsOpacity: false)
                    ColorPicker("Background Color 2", selection: $customColor2, supportsOpacity: false)
                }

                Button {
                    showPhotoPicker = true
                } label: {
                    Label(previewBgImage == nil ? "Choose Custom Background Photo" : "Change Custom Background Photo", systemImage: "photo.on.rectangle.angled")
                }

                if let previewBgImage {
                    HStack(spacing: 12) {
                        Image(uiImage: previewBgImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 48)
                            .cornerRadius(8)
                            .clipped()

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Custom Background Active")
                                .font(.subheadline.weight(.medium))
                            Text("Blur \(Int(bgBlur)) · Dim \(Int(bgDim * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            self.previewBgImage = nil
                            configuration.saveMenuBackgroundImage(nil)
                            if menuThemePreset == "customImage" {
                                menuThemePreset = "appleIntelligence"
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Photo Blur")
                            Spacer()
                            Text("\(Int(bgBlur))")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $bgBlur, in: 0 ... 18, step: 1)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Dark Overlay (Readability)")
                            Spacer()
                            Text("\(Int(bgDim * 100))%")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $bgDim, in: 0.1 ... 0.85, step: 0.05)
                    }
                }

                Toggle("Animated Mesh Background", isOn: $animatedBg)
            } header: {
                Text("WriteNow Menu Theme & Wallpaper")
            } footer: {
                Text("Customize the prompt menu background with themes, custom gradient colors, or your own photo.")
            }

            // Text Apply Animations
            Section {
                ForEach(animationStyleOptions, id: \.id) { item in
                    Button {
                        textAnimationStyle = item.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: textAnimationStyle == item.id ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(textAnimationStyle == item.id ? accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                                Text(item.subtitle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Text Replace Animation (Accept / Append)")
            } footer: {
                Text("Visual effect played directly on the selected text when applying AI improvements.")
            }

            Section {
                HStack {
                    Text("Menu Button Title")
                    Spacer()
                    TextField("Write Now", text: $menuTitle)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Preset Grid Columns", selection: $gridColumns) {
                    Text("2 Columns").tag(2)
                    Text("3 Columns").tag(3)
                }
                Picker("Popover Size", selection: $sizePreset) {
                    Text("Compact").tag("compact")
                    Text("Standard").tag("standard")
                    Text("Large").tag("large")
                }
            } header: {
                Text("Menu Layout & Title")
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
        .tint(accentColor)
        .accentColor(accentColor)
        .navigationTitle("Themes & Customization")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPhotoPicker) {
            PhotoLibraryPicker { image in
                if let jpegData = Self.compressBackgroundImage(image) {
                    previewBgImage = UIImage(data: jpegData)
                    configuration.saveMenuBackgroundImage(jpegData)
                    menuThemePreset = "customImage"
                }
            }
        }
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
        .onChange(of: textAnimationStyle) { _ in commitSettings() }
        .onChange(of: menuThemePreset) { _ in commitSettings() }
        .onChange(of: customColor1) { _ in commitSettings() }
        .onChange(of: customColor2) { _ in commitSettings() }
        .onChange(of: bgBlur) { _ in commitSettings() }
        .onChange(of: bgDim) { _ in commitSettings() }
        .onChange(of: accentColor) { _ in commitSettings() }
        .alert(backupAlertTitle, isPresented: $showBackupAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupAlertMessage)
        }
    }

    private static func compressBackgroundImage(_ image: UIImage) -> Data? {
        let maxDim: CGFloat = 960
        let size = image.size
        let scale = min(1.0, maxDim / max(size.width, size.height))
        let targetSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.78)
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
            s.textAnimationStyle = textAnimationStyle
            s.menuThemePreset = menuThemePreset
            s.menuCustomColorHex1 = customColor1.hexRGBString
            s.menuCustomColorHex2 = customColor2.hexRGBString
            s.menuBgImageBlur = bgBlur
            s.menuBgImageDim = bgDim
            s.accentColorHex = accentColor.hexRGBString
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
        textAnimationStyle = s.textAnimationStyle
        menuThemePreset = s.menuThemePreset
        customColor1 = Color(hexString: s.menuCustomColorHex1, fallback: .blue)
        customColor2 = Color(hexString: s.menuCustomColorHex2, fallback: .indigo)
        bgBlur = s.menuBgImageBlur
        bgDim = s.menuBgImageDim
        accentColor = Color(hexString: s.accentColorHex, fallback: .blue)
    }
}

private struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onPicked: (UIImage) -> Void
        let dismiss: DismissAction

        init(onPicked: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onPicked = onPicked
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let img = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                onPicked(img)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            dismiss()
        }
    }
}

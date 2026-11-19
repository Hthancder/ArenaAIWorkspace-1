//
//  WriteNowRootView.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/15.
//

import Combine
import MessageUI
import PhotosUI
import SwiftUI
import SwiftUIIntrospect
import UIKit

private enum RootActiveSheet: Identifiable {
    case addEndpoint
    case editEndpoint(Configuration.Endpoint)
    case addPreset
    case editPreset(Configuration.WritingPreset)
    case mailComposer

    var id: String {
        switch self {
        case .addEndpoint: return "add-ep"
        case let .editEndpoint(ep): return "edit-ep-\(ep.id.uuidString)"
        case .addPreset: return "add-preset"
        case let .editPreset(p): return "edit-preset-\(p.id.uuidString)"
        case .mailComposer: return "mail"
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

    @ObservedObject var configuration = Configuration.shared
    @ObservedObject var configurationViewModel = Configuration.shared.viewModel
    @ObservedObject var appViewModel = WriteNowAppModel.shared

    init(scrollViewSubject: CurrentValueSubject<UIScrollView?, Never>? = nil) {
        self.scrollViewSubject = scrollViewSubject
    }

    @State var serviceStatus: ServiceStatus = .disconnected
    @State private var activeSheet: RootActiveSheet?

    @State private var serviceError: String = ""
    @State private var daemonMetricsSummary: String = ""
    @State private var daemonReachable: Bool = true
    @State private var testStatusMessage: String = ""
    @State private var testStatusOK: Bool = false
    @State private var isTestingActive: Bool = false
    @State private var isTestingAllEndpoints: Bool = false
    @State private var allEndpointsHealthSummary: String = ""
    @State private var groupMergeFeedback: String = ""
    @State private var isReorderingPresets: Bool = false

    @State private var showResetPresetsAlert = false
    @State private var mailResult: Result<MFMailComposeResult, Error>? = nil

    let statusTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            creditSection
            serviceSection
            endpointsSection
            themeAndEffectsSection
            sttNavigationSection
            presetsSection
            behaviorSection
            testSceneSection
            footerSection
        }
        .listStyle(.insetGrouped)
        .introspect(.list, on: .iOS(.v13, .v14, .v15)) { tableView in
            scrollViewSubject?.send(tableView)
        }
        .introspect(.list, on: .iOS(.v16, .v17, .v18)) { collectionView in
            scrollViewSubject?.send(collectionView)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addEndpoint:
                AddEndpointView(editingEndpoint: nil)
            case let .editEndpoint(endpoint):
                AddEndpointView(editingEndpoint: endpoint)
            case .addPreset:
                PresetEditorView(editingPreset: nil)
            case let .editPreset(preset):
                PresetEditorView(editingPreset: preset)
            case .mailComposer:
                MailView(result: $mailResult) { composer in
                    composer.setToRecipients(["example@example.com"])
                    composer.setSubject("Feedback")
                    composer.setMessageBody("Hello, WriteNow!", isHTML: false)
                }
            }
        }
        .alert("Reset All Presets?", isPresented: $showResetPresetsAlert) {
            Button("Reset", role: .destructive) {
                configuration.resetAllPresetsToDefault()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces all custom and modified presets with the built-in default presets (including Read-Only presets).")
        }
        .onAppear {
            DispatchQueue.main.async {
                if Bundle.main.bundleIdentifier == "wiki.qaq.AIGate" {
                    _ = GateSessionDelegate()
                }
                updateStatus()
            }
        }
        .onReceive(statusTimer) { _ in
            updateStatus()
        }
        .navigationTitle(NSLocalizedString("Write Now", bundle: Bundle.wrti_support, comment: ""))
        .accentColor(Color.accent)
    }

    // MARK: - Credit Section

    var creditSection: some View {
        Section {
            CreditBannerView(accentColor: Color(hexString: configurationViewModel.uiSettings.accentColorHex) ?? .accent)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Service Section

    var serviceSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { configuration.isEnabled },
                    set: { configuration.isEnabled = $0 }
                )
            ) {
                Text(NSLocalizedString("Enable Service", bundle: Bundle.wrti_support, comment: ""))
            }
            .tint(Color.accent)

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

            if !daemonMetricsSummary.isEmpty {
                HStack {
                    Label("Metrics", systemImage: "speedometer")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(daemonMetricsSummary)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            if !serviceError.isEmpty {
                Text(serviceError)
                    .font(.footnote)
                    .foregroundColor(.red)
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

    // MARK: - Providers & Endpoints Section

    var endpointsSection: some View {
        Section {
            ForEach(configurationViewModel.uiEndpoints) { ep in
                EndpointButton(endpoint: ep) {
                    activeSheet = .editEndpoint(ep)
                }
            }
            .onDelete { offsets in
                let current = configurationViewModel.uiEndpoints
                for idx in offsets where current.indices.contains(idx) {
                    configuration.remove(current[idx])
                }
            }

            if configuration.hasDuplicateProviderEndpoints {
                Button {
                    let merged = configuration.groupSameProviderEndpoints()
                    groupMergeFeedback = merged > 0
                        ? "Merged \(merged) duplicate endpoint(s) into unified providers."
                        : ""
                } label: {
                    Label("Group Same-Provider Models", systemImage: "rectangle.stack.badge.plus")
                        .foregroundColor(Color.accent)
                }
            }

            if !groupMergeFeedback.isEmpty {
                Text(groupMergeFeedback)
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if configurationViewModel.uiEndpoints.count > 1 {
                Button {
                    testAllEndpoints()
                } label: {
                    HStack {
                        Label("Test All Providers", systemImage: "waveform.path.ecg")
                        Spacer()
                        if isTestingAllEndpoints {
                            ProgressView()
                        }
                    }
                }
                .disabled(isTestingAllEndpoints)

                if !allEndpointsHealthSummary.isEmpty {
                    Text(allEndpointsHealthSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                activeSheet = .addEndpoint
            } label: {
                Label("Add Provider / Endpoint", systemImage: "plus.circle.fill")
                    .foregroundColor(Color.accent)
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
            Text("One provider can hold multiple models. Tap a provider or model chip to activate immediately, or tap the slider icon to edit models.")
        }
    }

    // MARK: - Theme, Background & Text Animations Section

    var themeAndEffectsSection: some View {
        Section {
            NavigationLink {
                ThemeAppearanceView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "paintpalette.fill")
                        .foregroundColor(Color(hexString: configurationViewModel.uiSettings.accentColorHex) ?? .accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Theme, Background & Effects")
                            .font(.subheadline.weight(.medium))
                        Text("\(ThemeCatalog.displayName(for: configurationViewModel.uiSettings.menuThemePreset)) · \(AnimationCatalog.shortTitle(for: configurationViewModel.uiSettings.textReplacementAnimation))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        } header: {
            Text("Menu Theme & Animations")
        } footer: {
            Text("Customize the WriteNow menu theme, custom photo background, accent color palette, and text replacement animations.")
        }
    }

    // MARK: - Speech & Voice (STT) Section

    var sttNavigationSection: some View {
        let stt = configurationViewModel.uiSettings.stt
        let engineSummary: String = {
            if !stt.enabled { return "Disabled" }
            if stt.providerType == "apple_speech" { return "Apple Speech (Native)" }
            if stt.presetKind == "reuse_llm" { return "Reuse Active LLM" }
            return "\(stt.model.isEmpty ? "Whisper" : stt.model)"
        }()

        return Section {
            NavigationLink {
                STTSettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(stt.enabled ? Color.accent : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Speech & Voice (STT)")
                            .font(.subheadline.weight(.medium))
                        Text("\(engineSummary) · \(stt.sourceLanguage.uppercased()) → \(stt.targetLanguage.uppercased())")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
        } header: {
            Text("Voice Prompt & Dictation")
        } footer: {
            Text("Speak prompts, dictate text, or translate speech using Groq/OpenAI Whisper, custom OpenAI-compatible APIs, or Apple Speech.")
        }
    }

    // MARK: - Presets Section

    var presetsSection: some View {
        Section {
            ForEach(configurationViewModel.uiPresets) { preset in
                HStack(spacing: 10) {
                    Button {
                        activeSheet = .editPreset(preset)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: preset.icon)
                                .foregroundColor(preset.isEnabled ? Color.accent : .secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(preset.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(preset.isEnabled ? .primary : .secondary)
                                    if preset.availability != .both {
                                        Text(preset.availability.shortLabel)
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(preset.availability == .readOnlyOnly ? Color.cyan.opacity(0.16) : Color.secondary.opacity(0.14))
                                            .foregroundColor(preset.availability == .readOnlyOnly ? .cyan : .secondary)
                                            .cornerRadius(4)
                                    }
                                    if configuration.isPresetPinnedToSelectionMenu(preset.id) {
                                        Image(systemName: "pin.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(Color.accent)
                                    }
                                    if !preset.outputLanguage.isEmpty {
                                        Text(preset.outputLanguage)
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.accent.opacity(0.14))
                                            .foregroundColor(Color.accent)
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

                    if isReorderingPresets {
                        HStack(spacing: 6) {
                            Button {
                                configuration.movePreset(id: preset.id, delta: -1)
                            } label: {
                                Image(systemName: "arrow.up.circle")
                                    .foregroundColor(.accent)
                            }
                            .buttonStyle(.borderless)

                            Button {
                                configuration.movePreset(id: preset.id, delta: 1)
                            } label: {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundColor(.accent)
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        Toggle("", isOn: Binding(
                            get: { preset.isEnabled },
                            set: { newVal in
                                var updated = preset
                                updated.isEnabled = newVal
                                configuration.updatePreset(updated)
                            }
                        ))
                        .labelsHidden()
                        .tint(Color.accent)
                    }
                }
            }
            .onDelete { offsets in
                let list = configurationViewModel.uiPresets
                for idx in offsets where list.indices.contains(idx) {
                    configuration.deletePreset(id: list[idx].id)
                }
            }

            Button {
                activeSheet = .addPreset
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
                Button(isReorderingPresets ? "Done" : "Reorder") {
                    isReorderingPresets.toggle()
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(Color.accent)
            }
        } footer: {
            Text("Edit, reorder, hide, or delete any preset (including defaults). Use Restore Default Presets anytime to recover missing defaults.")
        }
    }

    // MARK: - Behavior Section

    var behaviorSection: some View {
        Section {
            NavigationLink {
                ReadOnlyAndMenuSettingsView()
            } label: {
                HStack {
                    Label("Read-Only, Menu & Quick Actions", systemImage: "hand.tap.fill")
                    Spacer()
                    let pinCount = configurationViewModel.uiSettings.selectionMenuItems.filter(\.isEnabled).count
                    Text("\(pinCount) pinned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            NavigationLink {
                BehaviorSettingsView()
            } label: {
                HStack {
                    Label("Behavior, Layout & Backup", systemImage: "gearshape.2.fill")
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

    // MARK: - Test Scene Section

    var testSceneSection: some View {
        Section {
            NavigationLink {
                TestTextView()
            } label: {
                Label(NSLocalizedString("Test Text Editor", bundle: Bundle.wrti_support, comment: ""), systemImage: "square.and.pencil")
            }

            if MFMailComposeViewController.canSendMail() {
                Button {
                    activeSheet = .mailComposer
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
            Text("WriteNow RootHide · v\(Bundle.wrti_packageVersion) · Improved by Hthan24 · Base by owngoal-dev")
        }
    }

    // MARK: - Actions

    private func testActiveEndpoint(_ endpoint: Configuration.Endpoint) {
        isTestingActive = true
        testStatusMessage = ""
        EndpointNetworkHelper.testChatEndpoint(
            baseURL: endpoint.url,
            token: endpoint.token,
            model: endpoint.model,
            pathMode: endpoint.pathMode,
            customHeaders: endpoint.customHeaders,
            timeoutSeconds: endpoint.timeoutSeconds
        ) { ok, _, _, message in
            isTestingActive = false
            testStatusOK = ok
            testStatusMessage = message
        }
    }

    private func testAllEndpoints() {
        let list = configurationViewModel.uiEndpoints
        guard !list.isEmpty else { return }
        isTestingAllEndpoints = true
        allEndpointsHealthSummary = "Testing \(list.count) provider(s)..."

        let group = DispatchGroup()
        let lock = NSLock()
        var results: [Int: String] = [:]

        for (idx, ep) in list.enumerated() {
            group.enter()
            EndpointNetworkHelper.testChatEndpoint(
                baseURL: ep.url,
                token: ep.token,
                model: ep.model,
                pathMode: ep.pathMode,
                customHeaders: ep.customHeaders,
                timeoutSeconds: min(20, max(10, ep.timeoutSeconds))
            ) { ok, _, latencyMs, _ in
                lock.lock()
                results[idx] = ok ? "\(ep.displayName): \(latencyMs)ms ✓" : "\(ep.displayName): Failed ✗"
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.isTestingAllEndpoints = false
            let ordered = list.indices.compactMap { results[$0] }
            self.allEndpointsHealthSummary = ordered.joined(separator: " · ")
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
                    let reqs = Int(decoded["total_requests"] ?? "0") ?? 0
                    let lat = Int(decoded["last_latency_ms"] ?? "0") ?? 0
                    let ep = decoded["last_endpoint"] ?? ""
                    let fb = Int(decoded["total_fallbacks"] ?? "0") ?? 0
                    if reqs > 0 {
                        var parts = ["\(reqs) req"]
                        if lat > 0 { parts.append("\(lat)ms") }
                        if !ep.isEmpty { parts.append(ep) }
                        if fb > 0 { parts.append("\(fb) fallback") }
                        self.daemonMetricsSummary = parts.joined(separator: " • ")
                    } else {
                        self.daemonMetricsSummary = ""
                    }
                }
            }
        }.resume()
    }
}

// MARK: - Animated Credit Banner View

struct CreditBannerView: View {
    let accentColor: Color

    @State private var orbDrift: CGFloat = -1.0
    @State private var shimmerOffset: CGFloat = -220
    @State private var pulseScale: CGFloat = 1.0
    @State private var spinAngle: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.19),
                    Color(red: 0.13, green: 0.09, blue: 0.25),
                    Color(red: 0.05, green: 0.14, blue: 0.24),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Ambient moving glow orbs
            Circle()
                .fill(accentColor.opacity(0.32))
                .frame(width: 150, height: 150)
                .blur(radius: 32)
                .offset(x: orbDrift * 70, y: -26)

            Circle()
                .fill(Color.cyan.opacity(0.24))
                .frame(width: 130, height: 130)
                .blur(radius: 28)
                .offset(x: -orbDrift * 65, y: 30)

            // Diagonal sweeping sheen
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.14), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 120)
            .rotationEffect(.degrees(20))
            .offset(x: shimmerOffset)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                AngularGradient(
                                    colors: [.cyan, .blue, .purple, .pink, .orange, .cyan],
                                    center: .center
                                ),
                                lineWidth: 2.5
                            )
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(spinAngle))

                        Image(systemName: "sparkles")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(pulseScale)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("OMNIAI ENHANCED")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(.cyan.opacity(0.95))
                        Text("Universal AI · Translate · OCR · Notes")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white.opacity(0.68))
                    }

                    Spacer()

                    Text("v\(Bundle.wrti_packageVersion)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.14))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }

                Text("Credit to Hthan24 for improve")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .shadow(color: accentColor.opacity(0.65), radius: 8, x: 0, y: 2)

                Text("and for owngoal-dev for nice opensource project !")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.10))
                    .cornerRadius(10)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.cyan.opacity(0.75), accentColor.opacity(0.85), .purple.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.6
                )
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                    orbDrift = 1.0
                }
                withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                    shimmerOffset = 220
                }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseScale = 1.15
                }
                withAnimation(.linear(duration: 6.0).repeatForever(autoreverses: false)) {
                    spinAngle = 360
                }
            }
        }
    }
}

// MARK: - Theme & Animation Catalogs

enum ThemeCatalog {
    struct ThemeSpec: Identifiable {
        let id: String
        let name: String
        let hexColors: [String]
    }

    static let presets: [ThemeSpec] = [
        .init(id: "midnight_ocean", name: "Midnight Ocean", hexColors: ["#0EA5E9", "#2563EB", "#1E1B4B", "#0F172A"]),
        .init(id: "aurora_borealis", name: "Aurora Borealis", hexColors: ["#10B981", "#06B6D4", "#6366F1", "#0B1120"]),
        .init(id: "sunset_amber", name: "Sunset Amber", hexColors: ["#F97316", "#EF4444", "#DB2777", "#1F1024"]),
        .init(id: "cyberpunk_neon", name: "Cyberpunk Neon", hexColors: ["#06B6D4", "#D946EF", "#7C3AED", "#09091A"]),
        .init(id: "obsidian_minimal", name: "Obsidian Minimal", hexColors: ["#475569", "#334155", "#1E293B", "#09090B"]),
        .init(id: "apple_intelligence", name: "Apple Pink/Glow", hexColors: ["#F86594", "#A855F7", "#3B82F6", "#181029"]),
        .init(id: "custom_colors", name: "Custom Palette", hexColors: ["#3B82F6", "#8B5CF6", "#06B6D4", "#0F172A"]),
    ]

    static func displayName(for id: String) -> String {
        presets.first { $0.id == id }?.name ?? "Midnight Ocean"
    }

    static func colors(for id: String, customHex: [String]) -> [Color] {
        if id == "custom_colors" {
            let parsed = customHex.compactMap { Color(hexString: $0) }
            if parsed.count >= 2 { return parsed }
        }
        let hexes = presets.first { $0.id == id }?.hexColors ?? presets[0].hexColors
        return hexes.compactMap { Color(hexString: $0) }
    }
}

enum AnimationCatalog {
    struct AnimSpec: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
    }

    static let items: [AnimSpec] = [
        .init(id: "apple_intelligence", title: "Apple Intelligence Glow", subtitle: "100% native snapshot morph with luminous prism wave", icon: "wand.and.stars.inverse"),
        .init(id: "scatter_assemble", title: "Scatter & Assemble", subtitle: "Old letters shatter & scatter everywhere, new text snaps in", icon: "sparkles.rectangle.stack"),
        .init(id: "rain_drop_rise", title: "Gravity Fall & Sprout", subtitle: "Old text falls down with gravity, new text sprouts upward", icon: "arrow.down.to.line.compact"),
        .init(id: "thanos_dust", title: "Ash & Dust (Snap)", subtitle: "Old text dissolves into drifting ash particles, new text rises", icon: "wind"),
        .init(id: "typewriter_wave", title: "Cyber Wave Typewriter", subtitle: "Glowing scanline sweep & wave-typed reveal", icon: "waveform.path.ecg"),
        .init(id: "flip_cascade", title: "3D Flip Cascade", subtitle: "Characters flip cleanly in 3D perspective wave", icon: "rectangle.portrait.rotate"),
        .init(id: "glitch_matrix", title: "Glitch Matrix", subtitle: "RGB cyber glitch scramble & snap decode", icon: "bolt.shield"),
        .init(id: "none", title: "None (Instant)", subtitle: "Replace immediately with no overlay animation", icon: "hare"),
    ]

    static func shortTitle(for id: String) -> String {
        items.first { $0.id == id }?.title ?? "Apple Intelligence Glow"
    }
}

// MARK: - Theme, Background & Animation Settings View

struct ThemeAppearanceView: View {
    @ObservedObject var configuration = Configuration.shared
    @ObservedObject var viewModel = Configuration.shared.viewModel

    @State private var accentColor: Color
    @State private var menuThemePreset: String
    @State private var backgroundMode: String
    @State private var customColor1: Color
    @State private var customColor2: Color
    @State private var customColor3: Color
    @State private var customColor4: Color
    @State private var solidColor: Color
    @State private var imageBlur: Double
    @State private var imageDim: Double
    @State private var selectedAnimation: String

    @State private var customImagePreview: UIImage?
    @State private var showPhotoPicker = false
    @State private var previewTrigger = UUID()
    @State private var previewPlayCount = 0
    @State private var statusBanner = ""

    private let accentSwatches: [(name: String, hex: String)] = [
        ("Blue", "#3B82F6"),
        ("Cyan", "#06B6D4"),
        ("Indigo", "#6366F1"),
        ("Emerald", "#10B981"),
        ("Amber", "#F59E0B"),
        ("Rose", "#F43F5E"),
        ("Pink", "#F86594"),
    ]

    init() {
        let s = Configuration.shared.appSettings
        _accentColor = State(initialValue: Color(hexString: s.accentColorHex) ?? .blue)
        _menuThemePreset = State(initialValue: s.menuThemePreset)
        _backgroundMode = State(initialValue: s.backgroundMode)
        let custom = s.customThemeColorsHex
        _customColor1 = State(initialValue: Color(hexString: custom.indices.contains(0) ? custom[0] : "#3B82F6") ?? .blue)
        _customColor2 = State(initialValue: Color(hexString: custom.indices.contains(1) ? custom[1] : "#8B5CF6") ?? .purple)
        _customColor3 = State(initialValue: Color(hexString: custom.indices.contains(2) ? custom[2] : "#06B6D4") ?? .cyan)
        _customColor4 = State(initialValue: Color(hexString: custom.indices.contains(3) ? custom[3] : "#0F172A") ?? .black)
        _solidColor = State(initialValue: Color(hexString: s.solidBackgroundHex) ?? .black)
        _imageBlur = State(initialValue: s.backgroundImageBlur)
        _imageDim = State(initialValue: s.backgroundImageDim)
        _selectedAnimation = State(initialValue: s.textReplacementAnimation)
        if let data = GlobalStorage.shared.loadBackgroundImage(), let img = UIImage(data: data) {
            _customImagePreview = State(initialValue: img)
        } else {
            _customImagePreview = State(initialValue: nil)
        }
    }

    private var previewColors: [Color] {
        ThemeCatalog.colors(
            for: menuThemePreset,
            customHex: [
                customColor1.hexString,
                customColor2.hexString,
                customColor3.hexString,
                customColor4.hexString,
            ]
        )
    }

    var body: some View {
        Form {
            Section {
                menuPreviewCard
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            } header: {
                Text("Live Menu Preview")
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(accentSwatches, id: \.hex) { item in
                            let c = Color(hexString: item.hex) ?? .blue
                            Button {
                                accentColor = c
                                commitThemeSettings()
                            } label: {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(c)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.primary.opacity(accentColor.hexString == item.hex ? 0.8 : 0), lineWidth: 2)
                                        )
                                    Text(item.name)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                }

                ColorPicker("Custom Accent Color", selection: $accentColor, supportsOpacity: false)
                    .onChange(of: accentColor) { _ in commitThemeSettings() }
            } header: {
                Text("Tweak Accent Color")
            }

            Section {
                Picker("Background Style", selection: $backgroundMode) {
                    Text("Animated Mesh").tag("mesh")
                    Text("Gradient").tag("gradient")
                    Text("Solid Color").tag("solid")
                    Text("Custom Image").tag("image")
                }
                .onChange(of: backgroundMode) { _ in commitThemeSettings() }

                if backgroundMode == "mesh" || backgroundMode == "gradient" {
                    ForEach(ThemeCatalog.presets) { theme in
                        Button {
                            menuThemePreset = theme.id
                            commitThemeSettings()
                        } label: {
                            HStack(spacing: 10) {
                                HStack(spacing: -6) {
                                    ForEach(theme.hexColors.prefix(3), id: \.self) { hex in
                                        Circle()
                                            .fill(Color(hexString: hex) ?? .blue)
                                            .frame(width: 18, height: 18)
                                            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                                    }
                                }
                                Text(theme.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if menuThemePreset == theme.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(accentColor)
                                }
                            }
                        }
                    }

                    if menuThemePreset == "custom_colors" {
                        ColorPicker("Palette Color 1", selection: $customColor1, supportsOpacity: false)
                            .onChange(of: customColor1) { _ in commitThemeSettings() }
                        ColorPicker("Palette Color 2", selection: $customColor2, supportsOpacity: false)
                            .onChange(of: customColor2) { _ in commitThemeSettings() }
                        ColorPicker("Palette Color 3", selection: $customColor3, supportsOpacity: false)
                            .onChange(of: customColor3) { _ in commitThemeSettings() }
                        ColorPicker("Palette Color 4", selection: $customColor4, supportsOpacity: false)
                            .onChange(of: customColor4) { _ in commitThemeSettings() }
                    }
                } else if backgroundMode == "solid" {
                    ColorPicker("Menu Background Color", selection: $solidColor, supportsOpacity: false)
                        .onChange(of: solidColor) { _ in commitThemeSettings() }
                } else if backgroundMode == "image" {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Choose Photo from Library", systemImage: "photo.on.rectangle.angled")
                    }

                    Button {
                        if let clipImg = UIPasteboard.general.image {
                            savePickedImage(clipImg)
                            statusBanner = "Applied background image from clipboard."
                        } else {
                            statusBanner = "No image found in clipboard."
                        }
                    } label: {
                        Label("Paste Image from Clipboard", systemImage: "doc.on.clipboard")
                    }

                    if customImagePreview != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Background Blur")
                                Spacer()
                                Text("\(Int(imageBlur))")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $imageBlur, in: 0 ... 24, step: 1)
                                .tint(accentColor)
                                .onChange(of: imageBlur) { _ in commitThemeSettings() }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Dark Dimming Overlay")
                                Spacer()
                                Text("\(Int(imageDim * 100))%")
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $imageDim, in: 0.0 ... 0.85, step: 0.05)
                                .tint(accentColor)
                                .onChange(of: imageDim) { _ in commitThemeSettings() }
                        }

                        Button(role: .destructive) {
                            customImagePreview = nil
                            configuration.updateBackgroundImage(nil)
                            backgroundMode = configuration.appSettings.backgroundMode
                            statusBanner = "Removed custom background photo."
                        } label: {
                            Label("Remove Custom Photo", systemImage: "trash")
                        }
                    }

                    if !statusBanner.isEmpty {
                        Text(statusBanner)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("OmniAI Menu Background")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    NativeAnimationPreviewBox(
                        style: selectedAnimation,
                        accentColor: UIColor(accentColor),
                        themeColors: previewThemeUIColors,
                        playCount: previewPlayCount
                    )
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        triggerAnimationPreview()
                    }

                    HStack {
                        Text("Tap the preview or pick an effect below to test.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            triggerAnimationPreview()
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(accentColor.opacity(0.14))
                                .foregroundColor(accentColor)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 4)

                ForEach(AnimationCatalog.items) { anim in
                    Button {
                        selectedAnimation = anim.id
                        commitThemeSettings()
                        triggerAnimationPreview()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: anim.icon)
                                .foregroundColor(selectedAnimation == anim.id ? accentColor : .secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(anim.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                                Text(anim.subtitle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedAnimation == anim.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(accentColor)
                            }
                        }
                    }
                }
            } header: {
                Text("Text Replacement Animation")
            } footer: {
                Text("Plays an overlay effect right on the selected text when you tap Accept or Append.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Theme & Effects")
        .navigationBarTitleDisplayMode(.inline)
        .tint(accentColor)
        .sheet(isPresented: $showPhotoPicker) {
            PhotoLibraryPicker { image in
                if let image {
                    savePickedImage(image)
                    statusBanner = "Custom photo saved & synced to WriteNow menu."
                }
            }
        }
    }

    private var previewThemeUIColors: [UIColor] {
        if backgroundMode == "solid" {
            let acc = UIColor(accentColor)
            let sol = UIColor(solidColor)
            return [acc, sol, acc.withAlphaComponent(0.75), sol]
        }
        return previewColors.map { UIColor($0) }
    }

    private var menuPreviewCard: some View {
        ZStack {
            if backgroundMode == "image", let img = customImagePreview {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .clipped()
                    .blur(radius: CGFloat(imageBlur))
                    .overlay(Color.black.opacity(imageDim))
            } else if backgroundMode == "solid" {
                solidColor
            } else {
                LinearGradient(
                    colors: previewColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            VStack(spacing: 10) {
                HStack {
                    Text(configuration.appSettings.menuTitle)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Spacer()
                    Text("Provider · Model")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.16))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    Text("Selected text highlight & menu theme follow your active palette.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(
                            LinearGradient(
                                colors: previewColors.prefix(2).map { $0.opacity(0.45) },
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(8)
                }

                HStack(spacing: 8) {
                    ForEach(["Proofread", "Rewrite"], id: \.self) { label in
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(accentColor.opacity(0.32))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            )
                            .cornerRadius(8)
                    }
                }
            }
            .padding(12)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func triggerAnimationPreview() {
        previewPlayCount += 1
        previewTrigger = UUID()
    }

    private func savePickedImage(_ image: UIImage) {
        let resized = downscaleImage(image, maxDimension: 1200)
        if let jpegData = resized.jpegData(compressionQuality: 0.85) {
            customImagePreview = UIImage(data: jpegData) ?? resized
            backgroundMode = "image"
            configuration.updateBackgroundImage(jpegData)
            commitThemeSettings()
        }
    }

    private func downscaleImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let ratio = maxDimension / longest
        let targetSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func commitThemeSettings() {
        let hex1 = customColor1.hexString
        let hex2 = customColor2.hexString
        let hex3 = customColor3.hexString
        let hex4 = customColor4.hexString
        let solidHex = solidColor.hexString
        let accentHex = accentColor.hexString
        configuration.updateSettings { s in
            s.accentColorHex = accentHex
            s.menuThemePreset = menuThemePreset
            s.backgroundMode = backgroundMode
            s.animatedBackground = (backgroundMode == "mesh")
            s.customThemeColorsHex = [hex1, hex2, hex3, hex4]
            s.solidBackgroundHex = solidHex
            s.backgroundImageBlur = imageBlur
            s.backgroundImageDim = imageDim
            s.textReplacementAnimation = selectedAnimation
        }
    }
}

// MARK: - PHPickerViewController Wrapper (iOS 14+)

private struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: PHPickerViewController, context _: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage?) -> Void

        init(onPick: @escaping (UIImage?) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self)
            else {
                onPick(nil)
                return
            }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    self.onPick(object as? UIImage)
                }
            }
        }
    }
}

// MARK: - Preset Editor Sheet

struct PresetEditorView: View {
    let editingPreset: Configuration.WritingPreset?

    @ObservedObject var configuration = Configuration.shared
    @Environment(\.dismiss) var dismiss

    @State private var title: String
    @State private var icon: String
    @State private var systemPrompt: String
    @State private var temperature: Double
    @State private var includeExamples: Bool
    @State private var outputLanguage: String
    @State private var insertBehavior: Configuration.WritingPreset.InsertBehavior
    @State private var isEnabled: Bool
    @State private var availability: Configuration.WritingPreset.Availability
    @State private var pinToSelectionMenu: Bool
    @State private var selectedEndpointID: UUID?
    @State private var modelOverride: String
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
        _availability = State(initialValue: editingPreset?.availability ?? .both)
        _pinToSelectionMenu = State(initialValue: editingPreset.map { Configuration.shared.isPresetPinnedToSelectionMenu($0.id) } ?? false)
        _selectedEndpointID = State(initialValue: editingPreset?.endpointID)
        _modelOverride = State(initialValue: editingPreset?.modelOverride ?? "")
    }

    private var selectedEndpointForOverride: Configuration.Endpoint? {
        if let id = selectedEndpointID {
            return configuration.allEndpointsSorted.first { $0.id == id }
        }
        return configuration.activatedEndpoint
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

                    Picker("Show In", selection: $availability) {
                        ForEach(Configuration.WritingPreset.Availability.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
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

                    Toggle("Pin Directly to Text Selection Menu", isOn: $pinToSelectionMenu)
                        .tint(.accent)
                } header: {
                    Text("Execution Options")
                }

                Section {
                    Picker("Provider", selection: $selectedEndpointID) {
                        Text("Use Global Active Provider").tag(UUID?.none)
                        ForEach(configuration.allEndpointsSorted) { ep in
                            Text(ep.displayName)
                                .tag(UUID?.some(ep.id))
                        }
                    }

                    HStack {
                        Text("Model Override")
                        Spacer()
                        TextField("Global Default", text: $modelOverride)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    if let ep = selectedEndpointForOverride, !ep.effectiveModels.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Button {
                                    modelOverride = ""
                                } label: {
                                    Text("Default (\(ep.model))")
                                        .font(.caption2)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(modelOverride.isEmpty ? Color.accent.opacity(0.22) : Color.secondary.opacity(0.12))
                                        .foregroundColor(modelOverride.isEmpty ? .accent : .primary)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.borderless)

                                ForEach(ep.effectiveModels.prefix(12), id: \.self) { m in
                                    Button {
                                        modelOverride = m
                                    } label: {
                                        Text(m)
                                            .font(.caption2)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 5)
                                            .background(modelOverride == m ? Color.accent.opacity(0.22) : Color.secondary.opacity(0.12))
                                            .foregroundColor(modelOverride == m ? .accent : .primary)
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Per-Preset Model Routing (Optional)")
                } footer: {
                    Text("Bind this preset to a faster or specialized provider/model (e.g. Haiku/Flash for Proofread, Claude/GPT-4o for Rewrite) without changing your global model.")
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
        let cleanModelOverride = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
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
            existing.availability = availability
            existing.endpointID = selectedEndpointID
            existing.modelOverride = cleanModelOverride
            configuration.updatePreset(existing)
            configuration.setPresetPinnedToSelectionMenu(existing, pinned: pinToSelectionMenu)
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
                isEnabled: isEnabled,
                endpointID: selectedEndpointID,
                modelOverride: cleanModelOverride,
                availability: availability
            )
            configuration.addPreset(preset)
            if pinToSelectionMenu {
                configuration.setPresetPinnedToSelectionMenu(preset, pinned: true)
            }
        }
        dismiss()
    }
}

// MARK: - Behavior, Layout & Backup View

struct BehaviorSettingsView: View {
    @ObservedObject var configuration = Configuration.shared
    @ObservedObject var viewModel = Configuration.shared.viewModel

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
    @State private var wordDiffEnabled: Bool
    @State private var defaultDiffMode: String
    @State private var clipboardContextEnabled: Bool
    @State private var autoAttachClipboardOnEmpty: Bool
    @State private var restoreLastSessionEnabled: Bool
    @State private var lastSessionTTLSeconds: Int
    @State private var keepEditContextEnabled: Bool
    @State private var editContextMatchMode: String
    @State private var editContextMaxTurns: Int
    @State private var editContextTTLSeconds: Int
    @State private var autoFallbackEndpointEnabled: Bool
    @State private var minimalUIMode: Bool
    @State private var uiShowInputPreview: Bool
    @State private var uiShowHeaderOCR: Bool
    @State private var uiShowAttachmentButton: Bool
    @State private var uiShowVoiceButton: Bool
    @State private var uiShowQuickActionsBar: Bool
    @State private var uiShowRecentBar: Bool
    @State private var uiShowSmartReplyButton: Bool
    @State private var uiShowPresetGrid: Bool
    @State private var uiShowOutputQuickActions: Bool
    @State private var uiShowOutputSpeakButton: Bool
    @State private var uiShowOutputDiffButton: Bool
    @State private var inPlaceOverlayEnabled: Bool

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
        _wordDiffEnabled = State(initialValue: s.wordDiffEnabled)
        _defaultDiffMode = State(initialValue: s.defaultDiffMode)
        _clipboardContextEnabled = State(initialValue: s.clipboardContextEnabled)
        _autoAttachClipboardOnEmpty = State(initialValue: s.autoAttachClipboardOnEmpty)
        _restoreLastSessionEnabled = State(initialValue: s.restoreLastSessionEnabled)
        _lastSessionTTLSeconds = State(initialValue: s.lastSessionTTLSeconds)
        _keepEditContextEnabled = State(initialValue: s.keepEditContextEnabled)
        _editContextMatchMode = State(initialValue: s.editContextMatchMode)
        _editContextMaxTurns = State(initialValue: s.editContextMaxTurns)
        _editContextTTLSeconds = State(initialValue: s.editContextTTLSeconds)
        _autoFallbackEndpointEnabled = State(initialValue: s.autoFallbackEndpointEnabled)
        _minimalUIMode = State(initialValue: s.minimalUIMode)
        _uiShowInputPreview = State(initialValue: s.uiShowInputPreview)
        _uiShowHeaderOCR = State(initialValue: s.uiShowHeaderOCR)
        _uiShowAttachmentButton = State(initialValue: s.uiShowAttachmentButton)
        _uiShowVoiceButton = State(initialValue: s.uiShowVoiceButton)
        _uiShowQuickActionsBar = State(initialValue: s.uiShowQuickActionsBar)
        _uiShowRecentBar = State(initialValue: s.uiShowRecentBar)
        _uiShowSmartReplyButton = State(initialValue: s.uiShowSmartReplyButton)
        _uiShowPresetGrid = State(initialValue: s.uiShowPresetGrid)
        _uiShowOutputQuickActions = State(initialValue: s.uiShowOutputQuickActions)
        _uiShowOutputSpeakButton = State(initialValue: s.uiShowOutputSpeakButton)
        _uiShowOutputDiffButton = State(initialValue: s.uiShowOutputDiffButton)
        _inPlaceOverlayEnabled = State(initialValue: s.inPlaceOverlayEnabled)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Menu Button Title")
                    Spacer()
                    TextField("OmniAI", text: $menuTitle)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Assistant Name & Menu Title")
            } footer: {
                Text("Title shown in the iOS menu and popover header (e.g. OmniAI, AI Assist, Translate).")
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
                Toggle("Auto-Fallback Provider on Error", isOn: $autoFallbackEndpointEnabled)
                Stepper("Request Timeout: \(timeout)s", value: $timeout, in: 15 ... 180, step: 15)
            } header: {
                Text("AI Behavior & Security")
            }

            Section {
                Toggle("Minimal UI Mode (Quick Translate / Ask)", isOn: $minimalUIMode)
                Picker("Popover Size", selection: $sizePreset) {
                    Text("Compact").tag("compact")
                    Text("Standard").tag("standard")
                    Text("Large").tag("large")
                    Text("Expanded (Full Width)").tag("expanded")
                }
                if !minimalUIMode && uiShowPresetGrid {
                    Picker("Preset Grid Columns", selection: $gridColumns) {
                        Text("2 Columns").tag(2)
                        Text("3 Columns").tag(3)
                    }
                }
                Toggle("In-Place Screen Overlay (On Screen)", isOn: $inPlaceOverlayEnabled)
                DisclosureGroup("Customize Visible UI Buttons") {
                    Toggle("Input Text Preview", isOn: $uiShowInputPreview)
                    Toggle("Header Screen OCR Button", isOn: $uiShowHeaderOCR)
                    Toggle("Attachment Menu (Photo / Camera / Region / File)", isOn: $uiShowAttachmentButton)
                    Toggle("Voice / Mic Bar", isOn: $uiShowVoiceButton)
                    Toggle("Quick Actions Bar", isOn: $uiShowQuickActionsBar)
                    Toggle("Recent Prompts Bar", isOn: $uiShowRecentBar)
                    Toggle("Smart Reply Button", isOn: $uiShowSmartReplyButton)
                    Toggle("Full Preset Grid", isOn: $uiShowPresetGrid)
                    Toggle("Output Refine Chips", isOn: $uiShowOutputQuickActions)
                    Toggle("Output Speak Button (TTS)", isOn: $uiShowOutputSpeakButton)
                    Toggle("Output Diff Button", isOn: $uiShowOutputDiffButton)
                }
            } header: {
                Text("Interface Layout & Minimal Mode")
            } footer: {
                Text("Minimal UI strips extra clutter down to a fast prompt bar + 1-tap action chips. You can also toggle layout and expand size directly inside the popover header.")
            }

            Section {
                Toggle("Enable Word-Level Diff", isOn: $wordDiffEnabled)
                if wordDiffEnabled {
                    Picker("Default Compare Mode", selection: $defaultDiffMode) {
                        Text("Off (Tap Diff to View)").tag("toggle_word")
                        Text("Auto-Show Word Diff").tag("auto_word")
                        Text("Auto-Show Split Original").tag("split")
                    }
                }
                Toggle("Enable Clipboard Context & Smart Reply", isOn: $clipboardContextEnabled)
                if clipboardContextEnabled {
                    Toggle("Auto-Attach Clipboard if Selection Empty", isOn: $autoAttachClipboardOnEmpty)
                }
                Toggle("Enable Restore Last Session", isOn: $restoreLastSessionEnabled)
                if restoreLastSessionEnabled {
                    Picker("Session Keep Duration", selection: $lastSessionTTLSeconds) {
                        Text("1 Minute").tag(60)
                        Text("3 Minutes").tag(180)
                        Text("5 Minutes").tag(300)
                        Text("10 Minutes").tag(600)
                        Text("Always Keep").tag(0)
                    }
                }
            } header: {
                Text("Diff, Smart Reply & Session")
            } footer: {
                Text("Restore Last Session keeps your generated draft if the menu closes accidentally, and clears automatically when you Accept or Discard.")
            }

            Section {
                Toggle("Keep Context from Previous Edits", isOn: $keepEditContextEnabled)
                if keepEditContextEnabled {
                    Picker("Attach Context When", selection: $editContextMatchMode) {
                        Text("Smart Match (Re-edited Text)").tag("smart_match")
                        Text("Always Within Time Window").tag("always_in_ttl")
                    }
                    Stepper("Max History Steps: \(editContextMaxTurns)", value: $editContextMaxTurns, in: 1 ... 5)
                    Picker("Memory Keep Duration", selection: $editContextTTLSeconds) {
                        Text("2 Minutes").tag(120)
                        Text("5 Minutes").tag(300)
                        Text("10 Minutes").tag(600)
                        Text("30 Minutes").tag(1800)
                        Text("Always Keep").tag(0)
                    }
                }
                Button(role: .destructive) {
                    UserDefaults.standard.removeObject(forKey: "WriteNowEditContextRecordsV1")
                    UserDefaults.standard.removeObject(forKey: "WriteNowEditContextRecordV1")
                    backupAlertTitle = "Edit Memory Cleared"
                    backupAlertMessage = "Saved edit history has been cleared."
                    showBackupAlert = true
                } label: {
                    Label("Clear Edit Memory", systemImage: "trash")
                }
            } header: {
                Text("Previous-Edit Context Memory")
            } footer: {
                Text("When you select and re-edit text that was previously improved (even after tapping Accept or Copy & Close), AI remembers the original text and prior edit steps.")
            }

            Section {
                Button {
                    if let data = configuration.exportBackupJSON(),
                       let str = String(data: data, encoding: .utf8)
                    {
                        UIPasteboard.general.string = str
                        backupAlertTitle = "Exported"
                        backupAlertMessage = "Full configuration JSON (providers, models, presets, settings) copied to clipboard."
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
        .listStyle(.insetGrouped)
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
        .onChange(of: wordDiffEnabled) { _ in commitSettings() }
        .onChange(of: defaultDiffMode) { _ in commitSettings() }
        .onChange(of: clipboardContextEnabled) { _ in commitSettings() }
        .onChange(of: autoAttachClipboardOnEmpty) { _ in commitSettings() }
        .onChange(of: restoreLastSessionEnabled) { _ in commitSettings() }
        .onChange(of: lastSessionTTLSeconds) { _ in commitSettings() }
        .onChange(of: keepEditContextEnabled) { _ in commitSettings() }
        .onChange(of: editContextMatchMode) { _ in commitSettings() }
        .onChange(of: editContextMaxTurns) { _ in commitSettings() }
        .onChange(of: editContextTTLSeconds) { _ in commitSettings() }
        .onChange(of: autoFallbackEndpointEnabled) { _ in commitSettings() }
        .onChange(of: minimalUIMode) { _ in commitSettings() }
        .onChange(of: uiShowInputPreview) { _ in commitSettings() }
        .onChange(of: uiShowHeaderOCR) { _ in commitSettings() }
        .onChange(of: uiShowAttachmentButton) { _ in commitSettings() }
        .onChange(of: uiShowVoiceButton) { _ in commitSettings() }
        .onChange(of: uiShowQuickActionsBar) { _ in commitSettings() }
        .onChange(of: uiShowRecentBar) { _ in commitSettings() }
        .onChange(of: uiShowSmartReplyButton) { _ in commitSettings() }
        .onChange(of: uiShowPresetGrid) { _ in commitSettings() }
        .onChange(of: uiShowOutputQuickActions) { _ in commitSettings() }
        .onChange(of: uiShowOutputSpeakButton) { _ in commitSettings() }
        .onChange(of: uiShowOutputDiffButton) { _ in commitSettings() }
        .onChange(of: inPlaceOverlayEnabled) { _ in commitSettings() }
        .alert(backupAlertTitle, isPresented: $showBackupAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupAlertMessage)
        }
    }

    private func commitSettings() {
        configuration.updateSettings { s in
            let cleanedTitle = menuTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            s.menuTitle = cleanedTitle.isEmpty ? "OmniAI" : cleanedTitle
            s.globalSystemPrompt = globalPrompt
            s.useFewShotExamples = useFewShot
            s.stripThinkingTags = stripThink
            s.streamingEnabled = streaming
            s.autoSelectAllIfEmpty = autoSelectAll
            s.maskEndpointKeys = !unmaskKeys
            s.requestTimeout = timeout
            s.gridColumns = gridColumns
            s.popoverSizePreset = sizePreset
            s.wordDiffEnabled = wordDiffEnabled
            s.defaultDiffMode = defaultDiffMode
            s.clipboardContextEnabled = clipboardContextEnabled
            s.autoAttachClipboardOnEmpty = autoAttachClipboardOnEmpty
            s.restoreLastSessionEnabled = restoreLastSessionEnabled
            s.lastSessionTTLSeconds = lastSessionTTLSeconds
            s.keepEditContextEnabled = keepEditContextEnabled
            s.editContextMatchMode = editContextMatchMode
            s.editContextMaxTurns = editContextMaxTurns
            s.editContextTTLSeconds = editContextTTLSeconds
            s.autoFallbackEndpointEnabled = autoFallbackEndpointEnabled
            s.minimalUIMode = minimalUIMode
            s.uiShowInputPreview = uiShowInputPreview
            s.uiShowHeaderOCR = uiShowHeaderOCR
            s.uiShowAttachmentButton = uiShowAttachmentButton
            s.uiShowVoiceButton = uiShowVoiceButton
            s.uiShowQuickActionsBar = uiShowQuickActionsBar
            s.uiShowRecentBar = uiShowRecentBar
            s.uiShowSmartReplyButton = uiShowSmartReplyButton
            s.uiShowPresetGrid = uiShowPresetGrid
            s.uiShowOutputQuickActions = uiShowOutputQuickActions
            s.uiShowOutputSpeakButton = uiShowOutputSpeakButton
            s.uiShowOutputDiffButton = uiShowOutputDiffButton
            s.inPlaceOverlayEnabled = inPlaceOverlayEnabled
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
        wordDiffEnabled = s.wordDiffEnabled
        defaultDiffMode = s.defaultDiffMode
        clipboardContextEnabled = s.clipboardContextEnabled
        autoAttachClipboardOnEmpty = s.autoAttachClipboardOnEmpty
        restoreLastSessionEnabled = s.restoreLastSessionEnabled
        lastSessionTTLSeconds = s.lastSessionTTLSeconds
        keepEditContextEnabled = s.keepEditContextEnabled
        editContextMatchMode = s.editContextMatchMode
        editContextMaxTurns = s.editContextMaxTurns
        editContextTTLSeconds = s.editContextTTLSeconds
        autoFallbackEndpointEnabled = s.autoFallbackEndpointEnabled
        minimalUIMode = s.minimalUIMode
        uiShowInputPreview = s.uiShowInputPreview
        uiShowHeaderOCR = s.uiShowHeaderOCR
        uiShowAttachmentButton = s.uiShowAttachmentButton
        uiShowVoiceButton = s.uiShowVoiceButton
        uiShowQuickActionsBar = s.uiShowQuickActionsBar
        uiShowRecentBar = s.uiShowRecentBar
        uiShowSmartReplyButton = s.uiShowSmartReplyButton
        uiShowPresetGrid = s.uiShowPresetGrid
        uiShowOutputQuickActions = s.uiShowOutputQuickActions
        uiShowOutputSpeakButton = s.uiShowOutputSpeakButton
        uiShowOutputDiffButton = s.uiShowOutputDiffButton
        inPlaceOverlayEnabled = s.inPlaceOverlayEnabled
    }
}

private struct NativeAnimationPreviewBox: UIViewRepresentable {
    let style: String
    let accentColor: UIColor
    let themeColors: [UIColor]
    let playCount: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PreviewContainerView {
        let container = PreviewContainerView()
        context.coordinator.container = container
        container.configureInitialText()
        return container
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        if context.coordinator.lastPlayCount != playCount {
            context.coordinator.lastPlayCount = playCount
            uiView.playAnimation(style: style, accentColor: accentColor, themeColors: themeColors)
        }
    }

    final class Coordinator {
        weak var container: PreviewContainerView?
        var lastPlayCount: Int = 0
    }
}

private final class PreviewContainerView: UIView {
    private let textView = UITextView()
    private let highlightLayer = CAGradientLayer()
    private weak var activeOverlay: UIView?
    private var showingAfter = false
    private var animationGeneration: Int = 0

    private let draftText = "Draft: Writing tools on iOS 15 should feel fast, fluid, and native across every single line of your text."
    private let polishedText = "Polished: Smooth native animations glide effortlessly across every line of your selected text!"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        clipsToBounds = true

        highlightLayer.opacity = 0
        highlightLayer.cornerRadius = 6
        layer.addSublayer(highlightLayer)

        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        textView.font = UIFont.systemFont(ofSize: 13.5, weight: .regular)
        textView.textColor = .label
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
        highlightLayer.frame = bounds.insetBy(dx: 6, dy: 6)
    }

    func configureInitialText() {
        showingAfter = false
        textView.text = draftText
    }

    func playAnimation(style: String, accentColor: UIColor, themeColors: [UIColor]) {
        layoutIfNeeded()
        animationGeneration += 1
        let gen = animationGeneration

        activeOverlay?.removeFromSuperview()
        activeOverlay = nil

        let colors = themeColors.isEmpty ? [accentColor, accentColor.withAlphaComponent(0.6)] : themeColors
        highlightLayer.colors = colors.prefix(3).map { $0.withAlphaComponent(0.32).cgColor }
        highlightLayer.startPoint = CGPoint(x: 0, y: 0)
        highlightLayer.endPoint = CGPoint(x: 1, y: 1)

        // Flash themed selection highlight briefly before replacing
        highlightLayer.opacity = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.animationGeneration == gen else { return }
            self.highlightLayer.opacity = 0
            self.runReplacement(style: style, accentColor: accentColor, themeColors: colors, generation: gen)
        }
    }

    private func runReplacement(style: String, accentColor: UIColor, themeColors: [UIColor], generation: Int) {
        guard bounds.width > 20, bounds.height > 20 else { return }

        let oldLines = visibleLineRects(in: textView)
        let beforeImage = capturePreviewImage()
        let beforeSnapshot = textView.resizableSnapshotView(from: textView.bounds, afterScreenUpdates: false, withCapInsets: .zero)

        showingAfter.toggle()
        textView.text = showingAfter ? polishedText : draftText
        textView.layoutIfNeeded()

        let normalized = style.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized != "none", !normalized.isEmpty else {
            return
        }

        let newLines = visibleLineRects(in: textView)
        let afterImage = capturePreviewImage()

        let overlay = UIView(frame: bounds)
        overlay.isUserInteractionEnabled = false
        overlay.clipsToBounds = true
        overlay.backgroundColor = .clear
        addSubview(overlay)
        activeOverlay = overlay

        if normalized == "apple_intelligence" {
            let afterSnapshot = textView.resizableSnapshotView(from: textView.bounds, afterScreenUpdates: true, withCapInsets: .zero)
            let beforeView: UIView = beforeSnapshot ?? {
                let iv = UIImageView(frame: bounds)
                iv.image = beforeImage
                return iv
            }()
            let afterView: UIView = afterSnapshot ?? {
                let iv = UIImageView(frame: bounds)
                iv.image = afterImage
                return iv
            }()
            beforeView.frame = bounds
            afterView.frame = bounds
            overlay.addSubview(beforeView)
            overlay.addSubview(afterView)

            let revealMask = CAGradientLayer()
            revealMask.frame = afterView.bounds
            revealMask.colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor]
            revealMask.locations = [-0.25, -0.10, 0.05]
            revealMask.startPoint = CGPoint(x: 0.3, y: 0.0)
            revealMask.endPoint = CGPoint(x: 0.7, y: 1.0)
            afterView.layer.mask = revealMask

            let bandHeight: CGFloat = 34
            let sweepBand = UIView(frame: CGRect(x: 0, y: -bandHeight * 0.5, width: bounds.width, height: bandHeight))
            let bandGrad = CAGradientLayer()
            bandGrad.frame = sweepBand.bounds
            bandGrad.colors = [
                UIColor(red: 0.97, green: 0.40, blue: 0.58, alpha: 0.0).cgColor,
                UIColor(red: 0.97, green: 0.40, blue: 0.58, alpha: 0.45).cgColor,
                UIColor(red: 0.66, green: 0.33, blue: 0.97, alpha: 0.55).cgColor,
                UIColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 0.42).cgColor,
                UIColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 0.0).cgColor,
            ]
            bandGrad.startPoint = CGPoint(x: 0, y: 0)
            bandGrad.endPoint = CGPoint(x: 1, y: 1)
            sweepBand.layer.addSublayer(bandGrad)
            overlay.addSubview(sweepBand)

            let locAnim = CABasicAnimation(keyPath: "locations")
            locAnim.fromValue = [-0.25, -0.10, 0.05]
            locAnim.toValue = [0.95, 1.12, 1.28]
            locAnim.duration = 0.60
            locAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            locAnim.fillMode = .forwards
            locAnim.isRemovedOnCompletion = false
            revealMask.add(locAnim, forKey: "aiSweepPreview")

            UIView.animate(withDuration: 0.60, delay: 0, options: [.curveEaseInOut]) {
                sweepBand.frame.origin.y = self.bounds.height - bandHeight * 0.35
                beforeView.alpha = 0
            } completion: { _ in
                UIView.animate(withDuration: 0.16) {
                    sweepBand.alpha = 0
                } completion: { _ in
                    if self.animationGeneration == generation {
                        overlay.removeFromSuperview()
                    }
                }
            }
            return
        }

        let bgColor = backgroundColor ?? .secondarySystemGroupedBackground
        let veil = UIView(frame: overlay.bounds)
        veil.backgroundColor = bgColor

        let maskPath = UIBezierPath()
        for line in (oldLines + newLines) {
            maskPath.append(UIBezierPath(roundedRect: line.insetBy(dx: -3, dy: -2), cornerRadius: 5))
        }
        let maskLayer = CAShapeLayer()
        maskLayer.frame = veil.bounds
        maskLayer.path = maskPath.cgPath
        veil.layer.mask = maskLayer

        let glow = CAGradientLayer()
        glow.frame = veil.bounds
        glow.colors = themeColors.prefix(3).map { $0.withAlphaComponent(0.22).cgColor }
        glow.startPoint = CGPoint(x: 0, y: 0)
        glow.endPoint = CGPoint(x: 1, y: 1)
        veil.layer.addSublayer(glow)

        overlay.addSubview(veil)

        let oldTiles = sliceTiles(image: beforeImage, lines: oldLines, backdropColor: bgColor)
        let newTiles = sliceTiles(image: afterImage, lines: newLines, backdropColor: bgColor)

        switch normalized {
        case "rain_drop_rise":
            for (idx, tile) in oldTiles.enumerated() {
                let iv = UIImageView(frame: tile.frame)
                iv.image = tile.image
                overlay.addSubview(iv)
                let delay = Double(tile.lineIndex) * 0.03 + Double(idx % 5) * 0.006
                UIView.animate(withDuration: 0.32, delay: delay, options: [.curveEaseIn]) {
                    iv.transform = CGAffineTransform(translationX: CGFloat.random(in: -10 ... 10), y: CGFloat.random(in: 30 ... 64))
                        .rotated(by: CGFloat.random(in: -0.3 ... 0.3))
                    iv.alpha = 0
                }
            }
            for (idx, tile) in newTiles.enumerated() {
                let iv = UIImageView(frame: tile.frame)
                iv.image = tile.image
                iv.transform = CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.92, y: 0.4)
                iv.alpha = 0
                overlay.addSubview(iv)
                let delay = 0.18 + Double(tile.lineIndex) * 0.03 + Double(idx % 5) * 0.006
                UIView.animate(withDuration: 0.42, delay: delay, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.85, options: [.curveEaseOut]) {
                    iv.transform = .identity
                    iv.alpha = 1
                }
            }
            finishOverlay(overlay, veil: veil, after: 0.82, generation: generation)

        case "thanos_dust":
            let emitter = CAEmitterLayer()
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
            emitter.emitterSize = bounds.size
            emitter.emitterShape = .rectangle
            let dot = makeDotCGImage()
            let ash = CAEmitterCell()
            ash.contents = dot
            ash.birthRate = 120
            ash.lifetime = 0.7
            ash.velocity = 40
            ash.velocityRange = 22
            ash.emissionLongitude = -CGFloat.pi / 4
            ash.emissionRange = CGFloat.pi / 2
            ash.yAcceleration = -55
            ash.xAcceleration = 45
            ash.scale = 0.3
            ash.scaleRange = 0.2
            ash.alphaSpeed = -1.4
            ash.color = UIColor.lightGray.cgColor
            let ember = CAEmitterCell()
            ember.contents = dot
            ember.birthRate = 55
            ember.lifetime = 0.6
            ember.velocity = 46
            ember.velocityRange = 24
            ember.emissionLongitude = -CGFloat.pi / 3
            ember.emissionRange = CGFloat.pi / 2
            ember.yAcceleration = -70
            ember.xAcceleration = 50
            ember.scale = 0.25
            ember.alphaSpeed = -1.5
            ember.color = accentColor.cgColor
            emitter.emitterCells = [ash, ember]
            overlay.layer.addSublayer(emitter)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { emitter.birthRate = 0 }

            let oldCount = max(1, oldTiles.count)
            for (idx, tile) in oldTiles.enumerated() {
                let iv = UIImageView(frame: tile.frame)
                iv.image = tile.image
                overlay.addSubview(iv)
                UIView.animate(withDuration: 0.34, delay: (Double(idx) / Double(oldCount)) * 0.24, options: [.curveEaseOut]) {
                    iv.transform = CGAffineTransform(translationX: CGFloat.random(in: 14 ... 48), y: CGFloat.random(in: -30 ... -8))
                        .scaledBy(x: 0.35, y: 0.35)
                    iv.alpha = 0
                }
            }
            let newCount = max(1, newTiles.count)
            for (idx, tile) in newTiles.enumerated() {
                let iv = UIImageView(frame: tile.frame)
                iv.image = tile.image
                iv.transform = CGAffineTransform(translationX: -8, y: 10).scaledBy(x: 0.85, y: 0.85)
                iv.alpha = 0
                overlay.addSubview(iv)
                UIView.animate(withDuration: 0.36, delay: 0.22 + (Double(idx) / Double(newCount)) * 0.22, options: [.curveEaseOut]) {
                    iv.transform = .identity
                    iv.alpha = 1
                }
            }
            finishOverlay(overlay, veil: veil, after: 0.85, generation: generation)

        case "typewriter_wave":
            let oldCount = max(1, oldTiles.count)
            for (idx, tile) in oldTiles.enumerated() {
                let iv = UIImageView(frame: tile.frame)
                iv.image = tile.image
                overlay.addSubview(iv)
                UIView.animate(withDuration: 0.18, delay: (Double(idx) / Double(oldCount)) * 0.20, options: [.curveEaseIn]) {
                    iv.alpha = 0
                    iv.transform = CGAffineTransform(translationX: 0, y: -4).scaledBy(x: 0.96, y: 0.96)
                }
            }
            let beam = UIView(frame: CGRect(x: 0, y: -14, width: bounds.width, height: 24))
            let beamGrad = CAGradientLayer()
            beamGrad.frame = beam.bounds
            beamGrad.colors = [
                accentColor.withAlphaComponent(0).cgColor,
                accentColor.withAlphaComponent(0.55).cgColor,
                UIColor.white.withAlphaComponent(0.6).cgColor,
                accentColor.withAlphaComponent(0).cgColor,
            ]
            beam.layer.addSublayer(beamGrad)
            overlay.addSubview(beam)
            UIView.animate(withDuration: 0.50, delay: 0.04, options: [.curveEaseInOut]) {
                beam.frame.origin.y = self.bounds.height - 10
            } completion: { _ in
                UIView.animate(withDuration: 0.14) { beam.alpha = 0 }
            }
            let newCount = max(1, newTiles.count)
            for (idx, tile) in newTiles.enumerated() {
                let iv = UIImageView(frame: tile.frame)
                iv.image = tile.image
                iv.transform = CGAffineTransform(translationX: 0, y: 8).scaledBy(x: 0.96, y: 0.96)
                iv.alpha = 0
                overlay.addSubview(iv)
                UIView.animate(withDuration: 0.30, delay: 0.10 + (Double(idx) / Double(newCount)) * 0.32, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.5, options: [.curveEaseOut]) {
                    iv.transform = .identity
                    iv.alpha = 1
                }
            }
            finishOverlay(overlay, veil: veil, after: 0.76, generation: generation)

        case "flip_cascade":
            var perspective = CATransform3DIdentity
            perspective.m34 = -1.0 / 450.0
            let oldCount = max(1, oldTiles.count)
            for (idx, tile) in oldTiles.enumerated() {
                let iv = UIImageView(frame: tile.frame)
                iv.image = tile.image
                iv.layer.transform = perspective
                overlay.addSubview(iv)
                UIView.animate(withDuration: 0.20, delay: (Double(idx) / Double(oldCount)) * 0.18, options: [.curveEaseIn]) {
                    iv.layer.transform = CATransform3DRotate(perspective, .pi / 2.0, 1, 0, 0)
                    iv.alpha = 0
                }
            }
            let newCount = max(1, newTiles.count)
            for (idx, tile) in newTiles.enumerated() {
                let iv = UIImageView(frame: tile.frame)
                iv.image = tile.image
                iv.layer.transform = CATransform3DRotate(perspective, -.pi / 2.0, 1, 0, 0)
                iv.alpha = 0
                overlay.addSubview(iv)
                UIView.animate(withDuration: 0.32, delay: 0.16 + (Double(idx) / Double(newCount)) * 0.22, usingSpringWithDamping: 0.76, initialSpringVelocity: 0.6, options: [.curveEaseOut]) {
                    iv.layer.transform = perspective
                    iv.alpha = 1
                }
            }
            finishOverlay(overlay, veil: veil, after: 0.74, generation: generation)

        case "glitch_matrix":
            var oldViews: [UIImageView] = []
            var cyanViews: [UIImageView] = []
            var accViews: [UIImageView] = []
            for tile in oldTiles {
                let main = UIImageView(frame: tile.frame)
                main.image = tile.image
                let cyan = UIImageView(frame: tile.frame.offsetBy(dx: -3, dy: 0))
                cyan.image = tile.image.withRenderingMode(.alwaysTemplate)
                cyan.tintColor = UIColor.cyan.withAlphaComponent(0.75)
                let acc = UIImageView(frame: tile.frame.offsetBy(dx: 3, dy: 0))
                acc.image = tile.image.withRenderingMode(.alwaysTemplate)
                acc.tintColor = accentColor.withAlphaComponent(0.75)
                overlay.addSubview(cyan)
                overlay.addSubview(acc)
                overlay.addSubview(main)
                oldViews.append(main)
                cyanViews.append(cyan)
                accViews.append(acc)
            }
            var newViews: [UIImageView] = []
            for tile in newTiles {
                let iv = UIImageView(frame: tile.frame)
                iv.image = tile.image
                iv.alpha = 0
                overlay.addSubview(iv)
                newViews.append(iv)
            }
            UIView.animate(withDuration: 0.09) {
                for (i, v) in oldViews.enumerated() { v.transform = CGAffineTransform(translationX: i % 2 == 0 ? 5 : -5, y: 0) }
                for (i, v) in cyanViews.enumerated() { v.transform = CGAffineTransform(translationX: i % 2 == 0 ? -7 : 6, y: -1) }
                for (i, v) in accViews.enumerated() { v.transform = CGAffineTransform(translationX: i % 2 == 0 ? 7 : -6, y: 1) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
                guard let self, self.animationGeneration == generation else { return }
                UIView.animate(withDuration: 0.12) {
                    oldViews.forEach { $0.alpha = 0 }
                    cyanViews.forEach { $0.alpha = 0 }
                    accViews.forEach { $0.alpha = 0 }
                }
                for (i, iv) in newViews.enumerated() {
                    iv.transform = CGAffineTransform(translationX: i % 2 == 0 ? -4 : 4, y: 0)
                    UIView.animate(withDuration: 0.22, delay: Double(i % 5) * 0.015, options: [.curveEaseOut]) {
                        iv.transform = .identity
                        iv.alpha = 1
                    }
                }
            }
            finishOverlay(overlay, veil: veil, after: 0.58, generation: generation)

        default: // "scatter_assemble"
            for (idx, tile) in oldTiles.enumerated() {
                let iv = UIImageView(frame: tile.frame)
                iv.image = tile.image
                overlay.addSubview(iv)
                let delay = min(0.16, Double(idx) * 0.005)
                UIView.animate(withDuration: 0.34, delay: delay, options: [.curveEaseOut]) {
                    iv.transform = CGAffineTransform(translationX: CGFloat.random(in: -70 ... 70), y: CGFloat.random(in: -45 ... 45))
                        .rotated(by: CGFloat.random(in: -0.7 ... 0.7))
                        .scaledBy(x: 0.45, y: 0.45)
                    iv.alpha = 0
                }
            }
            for (idx, tile) in newTiles.enumerated() {
                let iv = UIImageView(frame: tile.frame)
                iv.image = tile.image
                iv.transform = CGAffineTransform(translationX: CGFloat.random(in: -65 ... 65), y: CGFloat.random(in: -40 ... 40))
                    .rotated(by: CGFloat.random(in: -0.5 ... 0.5))
                    .scaledBy(x: 1.22, y: 1.22)
                iv.alpha = 0
                overlay.addSubview(iv)
                let delay = 0.14 + min(0.22, Double(idx) * 0.006)
                UIView.animate(withDuration: 0.44, delay: delay, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.75, options: [.curveEaseOut]) {
                    iv.transform = .identity
                    iv.alpha = 1
                }
            }
            finishOverlay(overlay, veil: veil, after: 0.78, generation: generation)
        }
    }

    private func finishOverlay(_ overlay: UIView, veil: UIView, after delay: TimeInterval, generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.animationGeneration == generation else {
                overlay.removeFromSuperview()
                return
            }
            UIView.animate(withDuration: 0.16) {
                veil.alpha = 0
                overlay.alpha = 0
            } completion: { _ in
                overlay.removeFromSuperview()
            }
        }
    }

    private func capturePreviewImage() -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = window?.screen.scale ?? UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { ctx in
            if !drawHierarchy(in: bounds, afterScreenUpdates: true) {
                layer.render(in: ctx.cgContext)
            }
        }
    }

    private func visibleLineRects(in tv: UITextView) -> [CGRect] {
        guard let range = tv.textRange(from: tv.beginningOfDocument, to: tv.endOfDocument) else { return [] }
        let raw = tv.selectionRects(for: range).map(\.rect)
            .filter { !$0.isEmpty && $0.width > 1.5 && $0.height > 2 }
            .sorted { $0.minY < $1.minY }
        var merged: [CGRect] = []
        for rect in raw {
            if let lastIdx = merged.indices.last {
                let last = merged[lastIdx]
                let overlap = min(last.maxY, rect.maxY) - max(last.minY, rect.minY)
                if overlap > min(last.height, rect.height) * 0.45 {
                    merged[lastIdx] = last.union(rect)
                    continue
                }
            }
            merged.append(rect)
        }
        return merged.map { $0.insetBy(dx: -2, dy: -1.5).intersection(bounds) }
            .filter { !$0.isEmpty }
    }

    private struct PreviewTile {
        let image: UIImage
        let frame: CGRect
        let lineIndex: Int
    }

    private func sliceTiles(image: UIImage?, lines: [CGRect], backdropColor: UIColor) -> [PreviewTile] {
        guard let cg = image?.cgImage, let scale = image?.scale else { return [] }
        var bgR: CGFloat = 0, bgG: CGFloat = 0, bgB: CGFloat = 0, bgA: CGFloat = 1
        backdropColor.resolvedColor(with: traitCollection).getRed(&bgR, green: &bgG, blue: &bgB, alpha: &bgA)
        let bgRGB = (UInt8(clamping: Int(bgR * 255)), UInt8(clamping: Int(bgG * 255)), UInt8(clamping: Int(bgB * 255)))

        var out: [PreviewTile] = []
        for (lineIdx, rect) in lines.enumerated() {
            let pxRect = CGRect(
                x: max(0, floor(rect.minX * scale)),
                y: max(0, floor(rect.minY * scale)),
                width: min(CGFloat(cg.width) - max(0, floor(rect.minX * scale)), ceil(rect.width * scale)),
                height: min(CGFloat(cg.height) - max(0, floor(rect.minY * scale)), ceil(rect.height * scale))
            )
            guard pxRect.width >= 2, pxRect.height >= 2, let lineCG = cg.cropping(to: pxRect) else { continue }

            let w = lineCG.width
            let h = lineCG.height
            var buffer = [UInt8](repeating: 0, count: w * h * 4)
            let cs = CGColorSpaceCreateDeviceRGB()
            let bi = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            guard let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: bi) else {
                continue
            }
            ctx.draw(lineCG, in: CGRect(x: 0, y: 0, width: w, height: h))
            var hasInk = [Bool](repeating: false, count: w)
            for y in 0 ..< h {
                for x in 0 ..< w {
                    let i = (y * w + x) * 4
                    let r = Int(buffer[i]), g = Int(buffer[i + 1]), b = Int(buffer[i + 2]), a = Int(buffer[i + 3])
                    guard a > 0 else { continue }
                    let diff = max(abs(r - Int(bgRGB.0)), max(abs(g - Int(bgRGB.1)), abs(b - Int(bgRGB.2))))
                    if diff <= 10 {
                        buffer[i] = 0; buffer[i + 1] = 0; buffer[i + 2] = 0; buffer[i + 3] = 0
                    } else {
                        hasInk[x] = true
                        if diff < 42 {
                            let na = max(0, min(255, (diff - 10) * 255 / 32))
                            buffer[i] = UInt8((r * na) / 255)
                            buffer[i + 1] = UInt8((g * na) / 255)
                            buffer[i + 2] = UInt8((b * na) / 255)
                            buffer[i + 3] = UInt8(na)
                        }
                    }
                }
            }
            guard let keyedCG = ctx.makeImage() else { continue }
            var splits: [CGFloat] = []
            let stepPx = max(16, Int(34 * scale))
            let radPx = max(8, Int(12 * scale))
            var cursor = stepPx
            while cursor < w - Int(12 * scale) {
                var chosen = cursor
                var bestDist = Int.max
                for x in max(10, cursor - radPx) ... min(w - 10, cursor + radPx) where !hasInk[x] {
                    if abs(x - cursor) < bestDist { bestDist = abs(x - cursor); chosen = x }
                }
                let pt = CGFloat(chosen) / scale
                if (splits.last.map { pt - $0 >= 10 } ?? (pt >= 10)), rect.width - pt >= 10 {
                    splits.append(pt)
                }
                cursor = chosen + stepPx
            }
            let boundsPt = [CGFloat(0)] + splits + [rect.width]
            for i in 0 ..< (boundsPt.count - 1) {
                let sPt = boundsPt[i], ePt = boundsPt[i + 1], cw = ePt - sPt
                guard cw >= 2 else { continue }
                let pxX = max(0, Int(floor(sPt * scale)))
                let pxW = min(keyedCG.width - pxX, Int(ceil(cw * scale)))
                guard pxW >= 2, let chunkCG = keyedCG.cropping(to: CGRect(x: pxX, y: 0, width: pxW, height: keyedCG.height)) else { continue }
                out.append(PreviewTile(
                    image: UIImage(cgImage: chunkCG, scale: scale, orientation: .up),
                    frame: CGRect(x: rect.minX + sPt, y: rect.minY, width: cw, height: rect.height),
                    lineIndex: lineIdx
                ))
            }
        }
        return out
    }

    private func makeDotCGImage() -> CGImage? {
        let size = CGSize(width: 8, height: 8)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}

// MARK: - Speech & Voice (STT) Settings

struct STTSettingsView: View {
    @ObservedObject var configuration = Configuration.shared
    @ObservedObject var viewModel = Configuration.shared.viewModel

    @State private var enabled: Bool
    @State private var providerType: String
    @State private var presetKind: String
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var showKey: Bool = false
    @State private var model: String
    @State private var pathMode: Configuration.Endpoint.PathMode
    @State private var customHeadersText: String
    @State private var timeoutSeconds: Int

    @State private var voiceMode: String
    @State private var sourceLanguage: String
    @State private var customSourceCode: String
    @State private var targetLanguage: String
    @State private var customTargetCode: String
    @State private var translationStrategy: String
    @State private var translationStyle: String

    @State private var promptHint: String
    @State private var temperature: Double
    @State private var audioFormat: String
    @State private var maxDurationSeconds: Int
    @State private var autoSendVoicePrompt: Bool
    @State private var appleOnDeviceOnly: Bool

    @State private var fetchedModels: [String] = []
    @State private var isFetchingModels: Bool = false
    @State private var isTestingAPI: Bool = false
    @State private var apiStatusText: String = ""
    @State private var apiStatusOK: Bool = true

    // Live Mic Test
    @State private var isRecordingTest: Bool = false
    @State private var isProcessingTest: Bool = false
    @State private var testDuration: Double = 0
    @State private var testLevels: [CGFloat] = Array(repeating: 0.12, count: 16)
    @State private var testTranscript: String = ""
    @State private var testFinalOutput: String = ""
    @State private var testProviderUsed: String = ""
    @State private var testError: String = ""
    @State private var testPollTimer: Timer? = nil

    private static let languageChoices: [(code: String, name: String)] = [
        ("auto", "Auto Detect"),
        ("vi", "Vietnamese (vi)"),
        ("en", "English (en)"),
        ("zh", "Chinese (zh)"),
        ("ja", "Japanese (ja)"),
        ("ko", "Korean (ko)"),
        ("fr", "French (fr)"),
        ("de", "German (de)"),
        ("es", "Spanish (es)"),
        ("th", "Thai (th)"),
        ("custom", "Custom ISO Code..."),
    ]

    private static let targetChoices: [(code: String, name: String)] = [
        ("vi", "Vietnamese (vi)"),
        ("en", "English (en)"),
        ("zh", "Chinese (zh)"),
        ("ja", "Japanese (ja)"),
        ("ko", "Korean (ko)"),
        ("fr", "French (fr)"),
        ("de", "German (de)"),
        ("es", "Spanish (es)"),
        ("th", "Thai (th)"),
        ("custom", "Custom Language..."),
    ]

    init() {
        let s = Configuration.shared.appSettings.stt
        _enabled = State(initialValue: s.enabled)
        _providerType = State(initialValue: s.providerType)
        _presetKind = State(initialValue: s.presetKind)
        _baseURL = State(initialValue: s.baseURL)
        _apiKey = State(initialValue: s.apiKey)
        _model = State(initialValue: s.model)
        _pathMode = State(initialValue: s.pathMode)
        if !s.customHeaders.isEmpty,
           let d = try? JSONSerialization.data(withJSONObject: s.customHeaders, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: d, encoding: .utf8)
        {
            _customHeadersText = State(initialValue: str)
        } else {
            _customHeadersText = State(initialValue: "")
        }
        _timeoutSeconds = State(initialValue: s.timeoutSeconds)
        _voiceMode = State(initialValue: s.voiceMode)

        let knownSrc = Self.languageChoices.map(\.code).filter { $0 != "custom" }
        if knownSrc.contains(s.sourceLanguage) {
            _sourceLanguage = State(initialValue: s.sourceLanguage)
            _customSourceCode = State(initialValue: "")
        } else {
            _sourceLanguage = State(initialValue: "custom")
            _customSourceCode = State(initialValue: s.sourceLanguage)
        }

        let knownDst = Self.targetChoices.map(\.code).filter { $0 != "custom" }
        if knownDst.contains(s.targetLanguage) {
            _targetLanguage = State(initialValue: s.targetLanguage)
            _customTargetCode = State(initialValue: "")
        } else {
            _targetLanguage = State(initialValue: "custom")
            _customTargetCode = State(initialValue: s.targetLanguage)
        }

        _translationStrategy = State(initialValue: s.translationStrategy)
        _translationStyle = State(initialValue: s.translationStyle)
        _promptHint = State(initialValue: s.promptHint)
        _temperature = State(initialValue: s.temperature)
        _audioFormat = State(initialValue: s.audioFormat)
        _maxDurationSeconds = State(initialValue: s.maxDurationSeconds)
        _autoSendVoicePrompt = State(initialValue: s.autoSendVoicePrompt)
        _appleOnDeviceOnly = State(initialValue: s.appleOnDeviceOnly)
    }

    private var accentColor: Color {
        Color(hexString: viewModel.uiSettings.accentColorHex) ?? .accent
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Voice & STT", isOn: $enabled)
                    .onChange(of: enabled) { _ in commitSTT() }

                Picker("Speech Engine", selection: $providerType) {
                    Text("OpenAI-Compatible API").tag("openai_compatible")
                    Text("Apple Speech (Native)").tag("apple_speech")
                }
                .onChange(of: providerType) { _ in commitSTT() }
            } header: {
                Text("General")
            } footer: {
                Text("Adds a Hold/Tap Mic button to Quick Prompts and Follow-up Refinements, plus Dictate & Voice Translate modes.")
            }

            if providerType == "openai_compatible" {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            presetChip(id: "groq", title: "Groq Whisper", icon: "bolt.fill") {
                                presetKind = "groq"
                                baseURL = "https://api.groq.com/openai"
                                model = "whisper-large-v3-turbo"
                                pathMode = .auto
                                commitSTT()
                            }
                            presetChip(id: "openai", title: "OpenAI", icon: "sparkles") {
                                presetKind = "openai"
                                baseURL = "https://api.openai.com"
                                model = "whisper-1"
                                pathMode = .auto
                                commitSTT()
                            }
                            presetChip(id: "reuse_llm", title: "Reuse LLM", icon: "arrow.triangle.2.circlepath") {
                                presetKind = "reuse_llm"
                                if model.isEmpty { model = "whisper-1" }
                                commitSTT()
                            }
                            presetChip(id: "custom", title: "Custom", icon: "server.rack") {
                                presetKind = "custom"
                                commitSTT()
                            }
                        }
                        .padding(.vertical, 3)
                    }

                    if presetKind == "reuse_llm" {
                        if let active = viewModel.uiActivatedEndpoint {
                            HStack {
                                Text("Using Active LLM")
                                Spacer()
                                Text(active.displayName)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Text("No active LLM endpoint configured yet.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Base URL or Full Audio Endpoint")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("https://api.groq.com/openai", text: $baseURL)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .keyboardType(.URL)
                                .onChange(of: baseURL) { _ in commitSTT() }
                        }

                        HStack {
                            if showKey {
                                TextField("API Key (optional for local)", text: $apiKey)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .onChange(of: apiKey) { _ in commitSTT() }
                            } else {
                                SecureField("API Key (optional for local)", text: $apiKey)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .onChange(of: apiKey) { _ in commitSTT() }
                            }
                            Button {
                                showKey.toggle()
                            } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }

                        Picker("Path Mode", selection: $pathMode) {
                            Text("Auto (/v1/audio/...)").tag(Configuration.Endpoint.PathMode.auto)
                            Text("Raw (exact URL)").tag(Configuration.Endpoint.PathMode.raw)
                        }
                        .onChange(of: pathMode) { _ in commitSTT() }
                    }

                    HStack {
                        TextField("STT Model (e.g. whisper-large-v3-turbo)", text: $model)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .onChange(of: model) { _ in commitSTT() }

                        Button {
                            fetchSTTModels()
                        } label: {
                            if isFetchingModels {
                                ProgressView()
                            } else {
                                Label("Fetch", systemImage: "arrow.clockwise")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isFetchingModels)
                    }

                    if !fetchedModels.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(fetchedModels, id: \.self) { m in
                                    Button {
                                        model = m
                                        commitSTT()
                                    } label: {
                                        Text(m)
                                            .font(.caption2.weight(.medium))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(model == m ? accentColor.opacity(0.22) : Color.secondary.opacity(0.14))
                                            .foregroundColor(model == m ? accentColor : .primary)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Headers JSON (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $customHeadersText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 54)
                            .onChange(of: customHeadersText) { _ in commitSTT() }
                    }

                    Stepper("Timeout: \(timeoutSeconds)s", value: $timeoutSeconds, in: 10 ... 180, step: 5)
                        .onChange(of: timeoutSeconds) { _ in commitSTT() }

                    Button {
                        testSTTConnection()
                    } label: {
                        HStack {
                            Label("Test STT API Connection", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            if isTestingAPI {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTestingAPI)

                    if !apiStatusText.isEmpty {
                        Text(apiStatusText)
                            .font(.caption)
                            .foregroundColor(apiStatusOK ? .green : .red)
                    }
                } header: {
                    Text("STT API Provider")
                } footer: {
                    Text("Compatible with OpenAI Whisper, Groq Whisper, faster-whisper-server, whisper.cpp server, Speaches, OneAPI, and any /v1/audio/transcriptions endpoint.")
                }
            } else {
                Section {
                    Toggle("Prefer On-Device Recognition", isOn: $appleOnDeviceOnly)
                        .onChange(of: appleOnDeviceOnly) { _ in commitSTT() }
                } header: {
                    Text("Apple Speech Options")
                } footer: {
                    Text("Uses Apple's built-in SFSpeechRecognizer inside the AIGate daemon without needing an external API key.")
                }
            }

            Section {
                Picker("Default Voice Mode", selection: $voiceMode) {
                    Text("Ask AI Prompt").tag("prompt")
                    Text("Dictate Text").tag("dictate")
                    Text("Speak & Translate").tag("translate")
                }
                .onChange(of: voiceMode) { _ in commitSTT() }

                Picker("Source Language", selection: $sourceLanguage) {
                    ForEach(Self.languageChoices, id: \.code) { item in
                        Text(item.name).tag(item.code)
                    }
                }
                .onChange(of: sourceLanguage) { _ in commitSTT() }

                if sourceLanguage == "custom" {
                    TextField("Source ISO code (e.g. pt, it, id)", text: $customSourceCode)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onChange(of: customSourceCode) { _ in commitSTT() }
                }

                Picker("Target Language (Translate)", selection: $targetLanguage) {
                    ForEach(Self.targetChoices, id: \.code) { item in
                        Text(item.name).tag(item.code)
                    }
                }
                .onChange(of: targetLanguage) { _ in commitSTT() }

                if targetLanguage == "custom" {
                    TextField("Target language (e.g. Russian, French)", text: $customTargetCode)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onChange(of: customTargetCode) { _ in commitSTT() }
                }

                Picker("Translation Engine", selection: $translationStrategy) {
                    Text("Auto Hybrid (Whisper→EN, LLM→Others)").tag("hybrid")
                    Text("Always Active LLM (Best Context)").tag("llm")
                    Text("Whisper /translations Only (EN)").tag("whisper_direct")
                }
                .onChange(of: translationStrategy) { _ in commitSTT() }

                Picker("Translation Tone", selection: $translationStyle) {
                    Text("Natural & Fluent").tag("natural")
                    Text("Formal & Polite").tag("formal")
                    Text("Concise").tag("concise")
                    Text("Literal").tag("literal")
                }
                .onChange(of: translationStyle) { _ in commitSTT() }
            } header: {
                Text("Languages & Translation")
            } footer: {
                Text("You can also switch Prompt / Dictate / Translate and Source → Target languages directly inside the WriteNow popup.")
            }

            Section {
                Toggle("Auto-run spoken prompt on stop", isOn: $autoSendVoicePrompt)
                    .onChange(of: autoSendVoicePrompt) { _ in commitSTT() }

                Picker("Audio Format", selection: $audioFormat) {
                    Text("M4A AAC 16kHz (Compact)").tag("m4a")
                    Text("WAV PCM 16kHz (Lossless)").tag("wav")
                }
                .onChange(of: audioFormat) { _ in commitSTT() }

                Picker("Max Recording Length", selection: $maxDurationSeconds) {
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                    Text("120 seconds").tag(120)
                }
                .onChange(of: maxDurationSeconds) { _ in commitSTT() }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Whisper Prompt Hint (optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Terms, names, bilingual hints (e.g. iOS, RootHide, WriteNow)", text: $promptHint)
                        .onChange(of: promptHint) { _ in commitSTT() }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Sampling Temperature")
                        Spacer()
                        Text(String(format: "%.2f", temperature))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $temperature, in: 0.0 ... 0.8, step: 0.05)
                        .tint(accentColor)
                        .onChange(of: temperature) { _ in commitSTT() }
                }
            } header: {
                Text("Recording & Recognition Tuning")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            if isRecordingTest {
                                stopLiveMicTest()
                            } else {
                                startLiveMicTest()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isRecordingTest ? "stop.circle.fill" : "mic.circle.fill")
                                    .font(.title3)
                                Text(isRecordingTest ? "Stop & Test" : (isProcessingTest ? "Processing..." : "Tap to Record Test"))
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isRecordingTest ? Color.red.opacity(0.18) : accentColor.opacity(0.16))
                            .foregroundColor(isRecordingTest ? .red : accentColor)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isProcessingTest)

                        if isRecordingTest {
                            Text(String(format: "%.1fs", testDuration))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)

                            HStack(spacing: 2) {
                                ForEach(0 ..< testLevels.count, id: \.self) { idx in
                                    Capsule()
                                        .fill(accentColor)
                                        .frame(width: 2.5, height: max(4, testLevels[idx] * 22))
                                }
                            }
                            .frame(height: 24)
                        } else if isProcessingTest {
                            ProgressView()
                        }

                        Spacer()

                        if isRecordingTest {
                            Button("Cancel") {
                                cancelLiveMicTest()
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                            .buttonStyle(.borderless)
                        }
                    }

                    if !testError.isEmpty {
                        Text(testError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    if !testTranscript.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Transcript (\(testProviderUsed))")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.secondary)
                            Text(testTranscript)
                                .font(.footnote)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.10))
                        .cornerRadius(8)
                    }

                    if !testFinalOutput.isEmpty && testFinalOutput != testTranscript {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Translated Output")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(accentColor)
                            Text(testFinalOutput)
                                .font(.footnote)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(accentColor.opacity(0.10))
                        .cornerRadius(8)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Live Microphone & STT Test")
            } footer: {
                Text("Tests real microphone recording through the AIGate daemon with your active engine, source, and target language.")
            }
        }
        .listStyle(.insetGrouped)
        .tint(accentColor)
        .navigationTitle("Speech & Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            testPollTimer?.invalidate()
            testPollTimer = nil
            if isRecordingTest {
                AIGateClient.sttCancel()
            }
        }
    }

    private func presetChip(id: String, title: String, icon: String, action: @escaping () -> Void) -> some View {
        let active = (presetKind == id)
        return Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(active ? accentColor : Color.secondary.opacity(0.14))
            .foregroundColor(active ? .white : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.borderless)
    }

    private var resolvedSourceLanguage: String {
        if sourceLanguage == "custom" {
            let trimmed = customSourceCode.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "auto" : trimmed
        }
        return sourceLanguage
    }

    private var resolvedTargetLanguage: String {
        if targetLanguage == "custom" {
            let trimmed = customTargetCode.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "vi" : trimmed
        }
        return targetLanguage
    }

    private func parsedHeaders() -> [String: String] {
        let raw = customHeadersText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            return [:]
        }
        return dict
    }

    private func commitSTT() {
        let headers = parsedHeaders()
        let src = resolvedSourceLanguage
        let dst = resolvedTargetLanguage
        configuration.updateSettings { s in
            s.stt.enabled = enabled
            s.stt.providerType = providerType
            s.stt.presetKind = presetKind
            s.stt.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            s.stt.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            s.stt.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
            s.stt.pathMode = pathMode
            s.stt.customHeaders = headers
            s.stt.timeoutSeconds = timeoutSeconds
            s.stt.voiceMode = voiceMode
            s.stt.sourceLanguage = src
            s.stt.targetLanguage = dst
            s.stt.translationStrategy = translationStrategy
            s.stt.translationStyle = translationStyle
            s.stt.promptHint = promptHint
            s.stt.temperature = temperature
            s.stt.audioFormat = audioFormat
            s.stt.maxDurationSeconds = maxDurationSeconds
            s.stt.autoSendVoicePrompt = autoSendVoicePrompt
            s.stt.appleOnDeviceOnly = appleOnDeviceOnly
        }
    }

    private func resolvedConnection() -> (url: URL, token: String, pathMode: Configuration.Endpoint.PathMode, headers: [String: String])? {
        if presetKind == "reuse_llm", let active = viewModel.uiActivatedEndpoint {
            return (active.url, active.token, active.pathMode, active.customHeaders)
        }
        guard let u = EndpointURLHelper.normalizeBaseURL(baseURL) else { return nil }
        return (u, apiKey.trimmingCharacters(in: .whitespacesAndNewlines), pathMode, parsedHeaders())
    }

    private func fetchSTTModels() {
        guard let conn = resolvedConnection() else {
            apiStatusOK = false
            apiStatusText = "Enter a valid Base URL first."
            return
        }
        isFetchingModels = true
        apiStatusText = ""
        EndpointNetworkHelper.fetchModels(
            baseURL: conn.url,
            token: conn.token,
            pathMode: conn.pathMode,
            customHeaders: conn.headers
        ) { result in
            isFetchingModels = false
            switch result {
            case let .success(models):
                let audioPreferred = models.filter {
                    let l = $0.lowercased()
                    return l.contains("whisper") || l.contains("transcribe") || l.contains("stt") || l.contains("audio")
                }
                fetchedModels = audioPreferred.isEmpty ? Array(models.prefix(15)) : audioPreferred
                if let first = fetchedModels.first, model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    model = first
                    commitSTT()
                }
                apiStatusOK = true
                apiStatusText = "Fetched \(fetchedModels.count) model(s)."
            case let .failure(err):
                apiStatusOK = false
                apiStatusText = err.localizedDescription
            }
        }
    }

    private func testSTTConnection() {
        guard let conn = resolvedConnection() else {
            apiStatusOK = false
            apiStatusText = "Enter a valid Base URL first."
            return
        }
        isTestingAPI = true
        apiStatusText = ""
        EndpointNetworkHelper.testSTTEndpoint(
            baseURL: conn.url,
            token: conn.token,
            model: model,
            pathMode: conn.pathMode,
            customHeaders: conn.headers,
            timeoutSeconds: timeoutSeconds
        ) { ok, _, _, msg in
            isTestingAPI = false
            apiStatusOK = ok
            apiStatusText = msg
        }
    }

    private func startLiveMicTest() {
        commitSTT()
        testError = ""
        testTranscript = ""
        testFinalOutput = ""
        testProviderUsed = ""
        testDuration = 0
        testLevels = Array(repeating: 0.12, count: 16)

        AIGateClient.sttStart { ok, err in
            if !ok {
                isRecordingTest = false
                testError = err ?? "Could not start microphone on AIGate daemon."
                return
            }
            isRecordingTest = true
            testPollTimer?.invalidate()
            testPollTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                guard isRecordingTest else {
                    testPollTimer?.invalidate()
                    testPollTimer = nil
                    return
                }
                AIGateClient.fetchSTTStatus { recording, dur, lvl, maxDur in
                    guard isRecordingTest else { return }
                    testDuration = dur
                    var next = testLevels
                    if !next.isEmpty {
                        next.removeFirst()
                        next.append(CGFloat(max(0.08, min(1.0, lvl))))
                        testLevels = next
                    }
                    if !recording && dur >= max(1.0, maxDur - 0.5) {
                        stopLiveMicTest()
                    }
                }
            }
        }
    }

    private func cancelLiveMicTest() {
        testPollTimer?.invalidate()
        testPollTimer = nil
        isRecordingTest = false
        AIGateClient.sttCancel()
    }

    private func stopLiveMicTest() {
        testPollTimer?.invalidate()
        testPollTimer = nil
        isRecordingTest = false
        isProcessingTest = true

        AIGateClient.sttStop(
            mode: voiceMode,
            sourceLanguage: resolvedSourceLanguage,
            targetLanguage: resolvedTargetLanguage
        ) { ok, transcript, finalText, provider, err in
            isProcessingTest = false
            if !ok {
                testError = err ?? "STT test failed."
                return
            }
            testTranscript = transcript
            testFinalOutput = finalText
            testProviderUsed = provider
        }
    }
}

// MARK: - Read-Only, Text Selection Menu & Quick Actions Settings View

private enum ReadOnlySettingsSheet: Identifiable {
    case addMenuItem
    case editMenuItem(Configuration.SelectionMenuItem)
    case addQuickAction
    case editQuickAction(Configuration.QuickActionItem)

    var id: String {
        switch self {
        case .addMenuItem: return "add-menu"
        case let .editMenuItem(item): return "edit-menu-\(item.id.uuidString)"
        case .addQuickAction: return "add-qa"
        case let .editQuickAction(item): return "edit-qa-\(item.id.uuidString)"
        }
    }
}

struct ReadOnlyAndMenuSettingsView: View {
    @ObservedObject var configuration = Configuration.shared
    @ObservedObject var viewModel = Configuration.shared.viewModel

    @State private var readOnlyEnabled: Bool
    @State private var readOnlyShowEditablePresets: Bool
    @State private var readOnlyPrimaryAction: String
    @State private var readOnlyShowSpeakButton: Bool
    @State private var speechRate: Double
    @State private var readOnlyShowShareButton: Bool
    @State private var showMainMenuItemInSelection: Bool
    @State private var showMainMenuItemOnReadOnly: Bool
    @State private var selectionMenuPresentationMode: String
    @State private var selectionMenuItems: [Configuration.SelectionMenuItem]
    @State private var quickActions: [Configuration.QuickActionItem]
    @State private var injectIntoContextMenus: Bool
    @State private var unlockBlockedSelection: Bool
    @State private var floatingPickerBubbleEnabled: Bool
    @State private var pickerTwoFingerLongPressEnabled: Bool
    @State private var pickerThreeFingerTapEnabled: Bool
    @State private var pickerStatusBarDoubleTapEnabled: Bool
    @State private var pickerShakeEnabled: Bool
    @State private var ocrLanguagesText: String

    @State private var activeSheet: ReadOnlySettingsSheet?
    @State private var isReorderingMenuItems = false
    @State private var isReorderingQuickActions = false

    init() {
        let s = Configuration.shared.appSettings
        _readOnlyEnabled = State(initialValue: s.readOnlyEnabled)
        _readOnlyShowEditablePresets = State(initialValue: s.readOnlyShowEditablePresets)
        _readOnlyPrimaryAction = State(initialValue: s.readOnlyPrimaryAction)
        _readOnlyShowSpeakButton = State(initialValue: s.readOnlyShowSpeakButton)
        _speechRate = State(initialValue: s.speechRate)
        _readOnlyShowShareButton = State(initialValue: s.readOnlyShowShareButton)
        _showMainMenuItemInSelection = State(initialValue: s.showMainMenuItemInSelection)
        _showMainMenuItemOnReadOnly = State(initialValue: s.showMainMenuItemOnReadOnly)
        _selectionMenuPresentationMode = State(initialValue: s.selectionMenuPresentationMode)
        _selectionMenuItems = State(initialValue: s.selectionMenuItems)
        _quickActions = State(initialValue: s.quickActions)
        _injectIntoContextMenus = State(initialValue: s.injectIntoContextMenus)
        _unlockBlockedSelection = State(initialValue: s.unlockBlockedSelection)
        _floatingPickerBubbleEnabled = State(initialValue: s.floatingPickerBubbleEnabled)
        _pickerTwoFingerLongPressEnabled = State(initialValue: s.pickerTwoFingerLongPressEnabled)
        _pickerThreeFingerTapEnabled = State(initialValue: s.pickerThreeFingerTapEnabled)
        _pickerStatusBarDoubleTapEnabled = State(initialValue: s.pickerStatusBarDoubleTapEnabled)
        _pickerShakeEnabled = State(initialValue: s.pickerShakeEnabled)
        _ocrLanguagesText = State(initialValue: s.ocrPreferredLanguages.joined(separator: ", "))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Read-Only Text Support", isOn: $readOnlyEnabled)
                if readOnlyEnabled {
                    Toggle("Show Editing Presets in Read-Only", isOn: $readOnlyShowEditablePresets)
                    Picker("Primary Output Action", selection: $readOnlyPrimaryAction) {
                        Text("Copy & Close").tag("copy_close")
                        Text("Copy Only").tag("copy")
                        Text("Share Sheet").tag("share")
                    }
                    Toggle("Show Speak (Read Aloud) Button", isOn: $readOnlyShowSpeakButton)
                    if readOnlyShowSpeakButton {
                        Picker("Speech Speed", selection: $speechRate) {
                            Text("0.85× Slow").tag(0.85)
                            Text("1.0× Normal").tag(1.0)
                            Text("1.15× Fast").tag(1.15)
                        }
                    }
                    Toggle("Show Share Button", isOn: $readOnlyShowShareButton)
                }
            } header: {
                Text("Read-Only Contexts (Safari, Mail, Notes, PDF, Chat)")
            } footer: {
                Text("Allows translating, explaining, summarizing, and free-form prompting on non-editable text with Copy/Share/Speak actions instead of Replace.")
            }

            if readOnlyEnabled {
                Section {
                    Toggle("Inject into App Long-Press Context Menus", isOn: $injectIntoContextMenus)
                    Toggle("Force-Unlock Blocked Selection (Web & UITextView)", isOn: $unlockBlockedSelection)
                } header: {
                    Text("Restricted & Copy-Only Components")
                } footer: {
                    Text("Adds WriteNow into app-custom long-press menus (e.g. Messenger, Telegram, X) and Copy-only menus. Force-Unlock enables text selection on locked UITextView and web pages.")
                }

                Section {
                    Toggle("3-Finger Tap Anywhere (Quick OCR)", isOn: $pickerThreeFingerTapEnabled)
                    Toggle("2-Finger Long Press Anywhere", isOn: $pickerTwoFingerLongPressEnabled)
                    Toggle("Double-Tap Status Bar Area", isOn: $pickerStatusBarDoubleTapEnabled)
                    Toggle("Shake Device for Screen OCR", isOn: $pickerShakeEnabled)
                    Toggle("Floating Screen Picker Button", isOn: $floatingPickerBubbleEnabled)

                    HStack {
                        Text("OCR Languages")
                        Spacer()
                        TextField("vi-VN, en-US, zh-Hans", text: $ocrLanguagesText)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                } header: {
                    Text("Universal Screen Text Picker & Offline OCR")
                } footer: {
                    Text("Works on ANY unselectable or uncopyable text (labels, SwiftUI views, locked chats, images, videos). Single-tap bubble to scan screen, double-tap bubble for instant full-screen OCR, or drag a box.")
                }
            }

            Section {
                Toggle("Show Main \"\(configuration.appSettings.menuTitle)\" Button", isOn: $showMainMenuItemInSelection)
                if showMainMenuItemInSelection && readOnlyEnabled {
                    Toggle("Show Main Button on Read-Only Text", isOn: $showMainMenuItemOnReadOnly)
                }
                Picker("iOS 16+ Menu Style", selection: $selectionMenuPresentationMode) {
                    Text("Inline Buttons").tag("inline")
                    Text("Expandable Submenu").tag("submenu")
                }

                ForEach(selectionMenuItems) { item in
                    HStack(spacing: 10) {
                        Button {
                            activeSheet = .editMenuItem(item)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.icon.isEmpty ? "sparkles" : item.icon)
                                    .foregroundColor(item.isEnabled ? .accent : .secondary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(item.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(item.isEnabled ? .primary : .secondary)
                                        Text(item.availability.shortLabel)
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.14))
                                            .foregroundColor(.secondary)
                                            .cornerRadius(4)
                                    }
                                    Text(menuItemSubtitle(item))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isReorderingMenuItems {
                            HStack(spacing: 6) {
                                Button {
                                    moveMenuItem(id: item.id, delta: -1)
                                } label: {
                                    Image(systemName: "arrow.up.circle").foregroundColor(.accent)
                                }
                                .buttonStyle(.borderless)
                                Button {
                                    moveMenuItem(id: item.id, delta: 1)
                                } label: {
                                    Image(systemName: "arrow.down.circle").foregroundColor(.accent)
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            Toggle("", isOn: Binding(
                                get: { item.isEnabled },
                                set: { val in
                                    if let idx = selectionMenuItems.firstIndex(where: { $0.id == item.id }) {
                                        selectionMenuItems[idx].isEnabled = val
                                        commit()
                                    }
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                }
                .onDelete { offsets in
                    selectionMenuItems.remove(atOffsets: offsets)
                    commit()
                }

                Button {
                    activeSheet = .addMenuItem
                } label: {
                    Label("Add Item to Text Selection Menu", systemImage: "plus.circle.fill")
                }
                .disabled(selectionMenuItems.count >= 12)
            } header: {
                HStack {
                    Text("Text Selection Menu Items (Up to 12)")
                    Spacer()
                    if selectionMenuItems.count > 1 {
                        Button(isReorderingMenuItems ? "Done" : "Reorder") {
                            isReorderingMenuItems.toggle()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accent)
                    }
                }
            } footer: {
                Text("Pin presets, custom prompts, Smart Reply, or Voice directly into the iOS Copy/Look Up popup bar for 1-tap launch.")
            }

            Section {
                ForEach(quickActions) { action in
                    HStack(spacing: 10) {
                        Button {
                            activeSheet = .editQuickAction(action)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: action.icon.isEmpty ? "bolt.fill" : action.icon)
                                    .foregroundColor(action.isEnabled ? .accent : .secondary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(action.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(action.isEnabled ? .primary : .secondary)
                                        Text(action.availability.shortLabel)
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.14))
                                            .foregroundColor(.secondary)
                                            .cornerRadius(4)
                                    }
                                    Text(action.instruction)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isReorderingQuickActions {
                            HStack(spacing: 6) {
                                Button {
                                    moveQuickAction(id: action.id, delta: -1)
                                } label: {
                                    Image(systemName: "arrow.up.circle").foregroundColor(.accent)
                                }
                                .buttonStyle(.borderless)
                                Button {
                                    moveQuickAction(id: action.id, delta: 1)
                                } label: {
                                    Image(systemName: "arrow.down.circle").foregroundColor(.accent)
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            Toggle("", isOn: Binding(
                                get: { action.isEnabled },
                                set: { val in
                                    if let idx = quickActions.firstIndex(where: { $0.id == action.id }) {
                                        quickActions[idx].isEnabled = val
                                        commit()
                                    }
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                }
                .onDelete { offsets in
                    quickActions.remove(atOffsets: offsets)
                    commit()
                }

                Button {
                    activeSheet = .addQuickAction
                } label: {
                    Label("Add Quick Action Chip", systemImage: "plus.circle.fill")
                }

                Button {
                    quickActions = Configuration.QuickActionItem.defaultItems
                    commit()
                } label: {
                    Label("Reset Quick Actions to Default", systemImage: "arrow.uturn.backward.circle")
                }
            } header: {
                HStack {
                    Text("Quick Actions & Refine Chips")
                    Spacer()
                    if quickActions.count > 1 {
                        Button(isReorderingQuickActions ? "Done" : "Reorder") {
                            isReorderingQuickActions.toggle()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accent)
                    }
                }
            } footer: {
                Text("Quick chips appear inside the WriteNow popover (above presets and below results) for 1-tap prompts and refinements.")
            }
        }
        .listStyle(.insetGrouped)
        .tint(.accent)
        .navigationTitle("Read-Only & Menu")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: readOnlyEnabled) { _ in commit() }
        .onChange(of: readOnlyShowEditablePresets) { _ in commit() }
        .onChange(of: readOnlyPrimaryAction) { _ in commit() }
        .onChange(of: readOnlyShowSpeakButton) { _ in commit() }
        .onChange(of: speechRate) { _ in commit() }
        .onChange(of: readOnlyShowShareButton) { _ in commit() }
        .onChange(of: showMainMenuItemInSelection) { _ in commit() }
        .onChange(of: showMainMenuItemOnReadOnly) { _ in commit() }
        .onChange(of: selectionMenuPresentationMode) { _ in commit() }
        .onChange(of: injectIntoContextMenus) { _ in commit() }
        .onChange(of: unlockBlockedSelection) { _ in commit() }
        .onChange(of: floatingPickerBubbleEnabled) { _ in commit() }
        .onChange(of: pickerTwoFingerLongPressEnabled) { _ in commit() }
        .onChange(of: pickerThreeFingerTapEnabled) { _ in commit() }
        .onChange(of: pickerStatusBarDoubleTapEnabled) { _ in commit() }
        .onChange(of: pickerShakeEnabled) { _ in commit() }
        .onChange(of: ocrLanguagesText) { _ in commit() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addMenuItem:
                SelectionMenuItemEditorView(editingItem: nil) { saved in
                    selectionMenuItems.append(saved)
                    commit()
                }
            case let .editMenuItem(item):
                SelectionMenuItemEditorView(editingItem: item) { saved in
                    if let idx = selectionMenuItems.firstIndex(where: { $0.id == saved.id }) {
                        selectionMenuItems[idx] = saved
                        commit()
                    }
                }
            case .addQuickAction:
                QuickActionEditorView(editingAction: nil) { saved in
                    quickActions.append(saved)
                    commit()
                }
            case let .editQuickAction(action):
                QuickActionEditorView(editingAction: action) { saved in
                    if let idx = quickActions.firstIndex(where: { $0.id == saved.id }) {
                        quickActions[idx] = saved
                        commit()
                    }
                }
            }
        }
    }

    private func menuItemSubtitle(_ item: Configuration.SelectionMenuItem) -> String {
        switch item.actionKind {
        case .preset:
            if let pid = item.presetID,
               let preset = viewModel.uiPresets.first(where: { $0.id == pid })
            {
                return "Preset: \(preset.title)"
            }
            return "Run Preset"
        case .customPrompt:
            return item.customPrompt.isEmpty ? "Custom Prompt" : item.customPrompt
        case .smartReply:
            return "Draft Smart Reply"
        case .voicePrompt:
            return "Start Voice Input"
        }
    }

    private func moveMenuItem(id: UUID, delta: Int) {
        guard let idx = selectionMenuItems.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + delta
        guard selectionMenuItems.indices.contains(target) else { return }
        selectionMenuItems.swapAt(idx, target)
        commit()
    }

    private func moveQuickAction(id: UUID, delta: Int) {
        guard let idx = quickActions.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + delta
        guard quickActions.indices.contains(target) else { return }
        quickActions.swapAt(idx, target)
        commit()
    }

    private func commit() {
        configuration.updateSettings { s in
            s.readOnlyEnabled = readOnlyEnabled
            s.readOnlyShowEditablePresets = readOnlyShowEditablePresets
            s.readOnlyPrimaryAction = readOnlyPrimaryAction
            s.readOnlyShowSpeakButton = readOnlyShowSpeakButton
            s.speechRate = speechRate
            s.readOnlyShowShareButton = readOnlyShowShareButton
            s.showMainMenuItemInSelection = showMainMenuItemInSelection
            s.showMainMenuItemOnReadOnly = showMainMenuItemOnReadOnly
            s.selectionMenuPresentationMode = selectionMenuPresentationMode
            s.selectionMenuItems = selectionMenuItems
            s.quickActions = quickActions
            s.injectIntoContextMenus = injectIntoContextMenus
            s.unlockBlockedSelection = unlockBlockedSelection
            s.floatingPickerBubbleEnabled = floatingPickerBubbleEnabled
            s.pickerTwoFingerLongPressEnabled = pickerTwoFingerLongPressEnabled
            s.pickerThreeFingerTapEnabled = pickerThreeFingerTapEnabled
            s.pickerStatusBarDoubleTapEnabled = pickerStatusBarDoubleTapEnabled
            s.pickerShakeEnabled = pickerShakeEnabled
            let parsedLangs = ocrLanguagesText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parsedLangs.isEmpty {
                s.ocrPreferredLanguages = parsedLangs
            }
        }
    }
}

// MARK: - Selection Menu Item Editor Sheet

private struct SelectionMenuItemEditorView: View {
    let editingItem: Configuration.SelectionMenuItem?
    let onSave: (Configuration.SelectionMenuItem) -> Void

    @ObservedObject var viewModel = Configuration.shared.viewModel
    @Environment(\.dismiss) var dismiss

    @State private var title: String
    @State private var icon: String
    @State private var actionKind: Configuration.SelectionMenuItem.ActionKind
    @State private var presetID: UUID?
    @State private var customPrompt: String
    @State private var availability: Configuration.WritingPreset.Availability
    @State private var isEnabled: Bool

    init(
        editingItem: Configuration.SelectionMenuItem?,
        onSave: @escaping (Configuration.SelectionMenuItem) -> Void
    ) {
        self.editingItem = editingItem
        self.onSave = onSave
        let defaultPreset = Configuration.shared.viewModel.uiPresets.first?.id
        _title = State(initialValue: editingItem?.title ?? "")
        _icon = State(initialValue: editingItem?.icon ?? "sparkles")
        _actionKind = State(initialValue: editingItem?.actionKind ?? .preset)
        _presetID = State(initialValue: editingItem?.presetID ?? defaultPreset)
        _customPrompt = State(initialValue: editingItem?.customPrompt ?? "")
        _availability = State(initialValue: editingItem?.availability ?? .both)
        _isEnabled = State(initialValue: editingItem?.isEnabled ?? true)
    }

    private var canSave: Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        if actionKind == .customPrompt {
            return !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text("Menu Title")
                        Spacer()
                        TextField("e.g. Dịch VN", text: $title)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("SF Symbol (iOS 16+)")
                        Spacer()
                        TextField("globe", text: $icon)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    Picker("Show In", selection: $availability) {
                        ForEach(Configuration.WritingPreset.Availability.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Toggle("Enabled", isOn: $isEnabled)
                } header: {
                    Text("Appearance & Scope")
                }

                Section {
                    Picker("Action", selection: $actionKind) {
                        ForEach(Configuration.SelectionMenuItem.ActionKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }

                    if actionKind == .preset {
                        Picker("Preset", selection: $presetID) {
                            ForEach(viewModel.uiPresets) { preset in
                                Text(preset.title).tag(UUID?.some(preset.id))
                            }
                        }
                        .onChange(of: presetID) { newID in
                            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               let hit = viewModel.uiPresets.first(where: { $0.id == newID })
                            {
                                title = hit.title
                                icon = hit.icon
                                availability = hit.availability
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Optional Custom Prompt (Combined)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextEditor(text: $customPrompt)
                                .frame(minHeight: 75)
                                .font(.body)
                        }
                    } else if actionKind == .customPrompt {
                        TextEditor(text: $customPrompt)
                            .frame(minHeight: 110)
                            .font(.body)
                    }
                } header: {
                    Text("Action Target")
                } footer: {
                    if actionKind == .customPrompt {
                        Text("Prompt executed immediately when you tap this item in the text selection bar.")
                    } else if actionKind == .preset {
                        Text("Leave extra prompt empty to run the preset alone, or add custom instructions to combine both.")
                    }
                }
            }
            .navigationTitle(editingItem == nil ? "Add Menu Item" : "Edit Menu Item")
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
        guard !cleanTitle.isEmpty else { return }
        let item = Configuration.SelectionMenuItem(
            id: editingItem?.id ?? UUID(),
            title: cleanTitle,
            icon: icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "sparkles" : icon.trimmingCharacters(in: .whitespacesAndNewlines),
            actionKind: actionKind,
            presetID: actionKind == .preset ? presetID : nil,
            customPrompt: customPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            availability: availability,
            isEnabled: isEnabled
        )
        onSave(item)
        dismiss()
    }
}

// MARK: - Quick Action Editor Sheet

private struct QuickActionEditorView: View {
    let editingAction: Configuration.QuickActionItem?
    let onSave: (Configuration.QuickActionItem) -> Void

    @Environment(\.dismiss) var dismiss

    @State private var title: String
    @State private var icon: String
    @State private var instruction: String
    @State private var availability: Configuration.WritingPreset.Availability
    @State private var showOnInputPanel: Bool
    @State private var showOnOutputRefine: Bool
    @State private var isEnabled: Bool

    init(
        editingAction: Configuration.QuickActionItem?,
        onSave: @escaping (Configuration.QuickActionItem) -> Void
    ) {
        self.editingAction = editingAction
        self.onSave = onSave
        _title = State(initialValue: editingAction?.title ?? "")
        _icon = State(initialValue: editingAction?.icon ?? "bolt.fill")
        _instruction = State(initialValue: editingAction?.instruction ?? "")
        _availability = State(initialValue: editingAction?.availability ?? .both)
        _showOnInputPanel = State(initialValue: editingAction?.showOnInputPanel ?? true)
        _showOnOutputRefine = State(initialValue: editingAction?.showOnOutputRefine ?? true)
        _isEnabled = State(initialValue: editingAction?.isEnabled ?? true)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text("Chip Title")
                        Spacer()
                        TextField("e.g. Dịch VN", text: $title)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("SF Symbol")
                        Spacer()
                        TextField("bolt.fill", text: $icon)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    Picker("Show In", selection: $availability) {
                        ForEach(Configuration.WritingPreset.Availability.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                } header: {
                    Text("Identity")
                }

                Section {
                    TextEditor(text: $instruction)
                        .frame(minHeight: 110)
                        .font(.body)
                } header: {
                    Text("Prompt / Refine Instruction")
                }

                Section {
                    Toggle("Show on Popover Input Bar", isOn: $showOnInputPanel)
                    Toggle("Show on Output Refine Bar", isOn: $showOnOutputRefine)
                    Toggle("Enabled", isOn: $isEnabled)
                } header: {
                    Text("Placement")
                }
            }
            .navigationTitle(editingAction == nil ? "Add Quick Action" : "Edit Quick Action")
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
        let cleanInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanInstruction.isEmpty else { return }
        let item = Configuration.QuickActionItem(
            id: editingAction?.id ?? UUID(),
            title: cleanTitle,
            icon: icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "bolt.fill" : icon.trimmingCharacters(in: .whitespacesAndNewlines),
            instruction: cleanInstruction,
            availability: availability,
            showOnInputPanel: showOnInputPanel,
            showOnOutputRefine: showOnOutputRefine,
            isEnabled: isEnabled
        )
        onSave(item)
        dismiss()
    }
}

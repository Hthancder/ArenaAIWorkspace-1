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
    @State private var daemonReachable: Bool = true
    @State private var testStatusMessage: String = ""
    @State private var testStatusOK: Bool = false
    @State private var isTestingActive: Bool = false
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
            Text("This replaces all custom and modified presets with the 5 built-in presets.")
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
                        Text("WRITENOW ENHANCED")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(.cyan.opacity(0.95))
                        Text("iOS 15 · RootHide Edition")
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
        .init(id: "scatter_assemble", title: "Scatter & Assemble", subtitle: "Old letters shatter & scatter everywhere, new text snaps in", icon: "sparkles.rectangle.stack"),
        .init(id: "rain_drop_rise", title: "Gravity Fall & Sprout", subtitle: "Old text falls down with gravity, new text sprouts upward", icon: "arrow.down.to.line.compact"),
        .init(id: "thanos_dust", title: "Ash & Dust (Snap)", subtitle: "Old text dissolves into drifting ash particles, new text rises", icon: "wind"),
        .init(id: "typewriter_wave", title: "Cyber Wave Typewriter", subtitle: "Glowing scanline sweep & wave-typed reveal", icon: "waveform.path.ecg"),
        .init(id: "flip_cascade", title: "3D Flip Cascade", subtitle: "Characters flip cleanly in 3D perspective wave", icon: "rectangle.portrait.rotate"),
        .init(id: "glitch_matrix", title: "Glitch Matrix", subtitle: "RGB cyber glitch scramble & snap decode", icon: "bolt.shield"),
        .init(id: "none", title: "None (Instant)", subtitle: "Replace immediately with no overlay animation", icon: "hare"),
    ]

    static func shortTitle(for id: String) -> String {
        items.first { $0.id == id }?.title ?? "Scatter & Assemble"
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
    @State private var previewShowAfter = false
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
                Text("WriteNow Menu Background")
            }

            Section {
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

                Button {
                    triggerAnimationPreview()
                } label: {
                    Label("Preview Selected Text Animation", systemImage: "play.circle.fill")
                        .foregroundColor(accentColor)
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
                    Text(previewShowAfter ? "Polished text rises smoothly!" : "Original draft text here...")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.white.opacity(0.14))
                        .cornerRadius(8)
                        .id(previewTrigger)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }

                HStack(spacing: 8) {
                    ForEach(["Proofread", "Rewrite"], id: \.self) { label in
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.15))
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
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            previewShowAfter.toggle()
            previewTrigger = UUID()
        }
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
    }

    var body: some View {
        Form {
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
            } header: {
                Text("Popover Layout (iPhone 7 Plus)")
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
    }
}

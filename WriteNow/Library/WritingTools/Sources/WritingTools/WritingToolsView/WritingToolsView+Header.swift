//
//  WritingToolsView+Header.swift
//  WritingTools
//

import SwiftUI
import UIKit

extension WritingToolsView {
    var selectedTextCount: Int {
        textProxy.selectedText.count
    }

    var textCountDescription: String {
        selectedTextCount > 1
            ? String(format: "%d characters".localized, selectedTextCount)
            : String(format: "%d character".localized, selectedTextCount)
    }

    var headerBrandTitle: String {
        let raw = cfg.settings.menuTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw == "Write\u{00A0}Now" || raw == "Write Now" {
            return "OmniAI".localized
        }
        return raw
    }

    var activeEndpointLabel: String {
        if let active = cfg.activeEndpoint {
            let shortModel = active.shortModelName
            if active.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return shortModel.isEmpty ? active.displayName : shortModel
            }
            return shortModel.isEmpty ? active.displayName : shortModel
        }
        return "Provider"
    }

    var title: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1.5) {
                Text(headerBrandTitle)
                    .lineLimit(1)
                    .font(.subheadline.bold())
                HStack(spacing: 5) {
                    Text(textCountDescription)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)

                    if textProxy.isReadOnly {
                        HStack(spacing: 2.5) {
                            Image(systemName: "eye")
                                .font(.system(size: 8, weight: .bold))
                            Text("Read-Only")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.cyan.opacity(0.24))
                        .foregroundColor(Color(red: 0.72, green: 0.96, blue: 1.0))
                        .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 2)

            if cfg.settings.readOnlyEnabled && cfg.settings.uiShowHeaderOCR {
                screenOCRButton
            }

            expandToggleButton

            uiCustomizeMenu

            providerQuickMenu

            closeButton
        }
    }

    var expandToggleButton: some View {
        Button {
            let next = !isPopoverExpanded
            isPopoverExpanded = next
            (Presenter.shared.activeToolController as? WritingToolController)?.setExpandedSize(next)
        } label: {
            Image(systemName: isPopoverExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isPopoverExpanded ? .cyan : .white.opacity(0.9))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .foregroundStyle(.white)
                        .opacity(isPopoverExpanded ? 0.22 : 0.14)
                )
        }
        .buttonStyle(.plain)
    }

    var uiCustomizeMenu: some View {
        Menu {
            Section("Interface Mode & Size") {
                Button {
                    cfg.updateUISettings { $0.minimalUIMode.toggle() }
                } label: {
                    Label(
                        cfg.settings.minimalUIMode ? "Switch to Full UI" : "Switch to Minimal UI",
                        systemImage: cfg.settings.minimalUIMode ? "rectangle.grid.2x2" : "bolt.horizontal.circle"
                    )
                }

                Menu {
                    ForEach(["compact", "standard", "large", "expanded"], id: \.self) { sizeKey in
                        Button {
                            cfg.updateUISettings { $0.popoverSizePreset = sizeKey }
                            let exp = sizeKey == "expanded"
                            isPopoverExpanded = exp
                            (Presenter.shared.activeToolController as? WritingToolController)?.setExpandedSize(exp)
                        } label: {
                            let label = sizeKey.capitalized
                            if cfg.settings.popoverSizePreset == sizeKey {
                                Label(label, systemImage: "checkmark")
                            } else {
                                Text(label)
                            }
                        }
                    }
                } label: {
                    Label("Default Size (\(cfg.settings.popoverSizePreset.capitalized))", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }

            Section("Visible Controls") {
                uiToggleButton("Input Preview", keyPath: \.uiShowInputPreview)
                uiToggleButton("Header OCR Button", keyPath: \.uiShowHeaderOCR)
                uiToggleButton("Attachment Menu", keyPath: \.uiShowAttachmentButton)
                uiToggleButton("Voice / Mic Bar", keyPath: \.uiShowVoiceButton)
                uiToggleButton("Quick Actions Bar", keyPath: \.uiShowQuickActionsBar)
                uiToggleButton("Recent Prompts Bar", keyPath: \.uiShowRecentBar)
                uiToggleButton("Smart Reply Button", keyPath: \.uiShowSmartReplyButton)
                uiToggleButton("Preset Grid", keyPath: \.uiShowPresetGrid)
            }

            Section("Output Controls") {
                uiToggleButton("Refine Chips", keyPath: \.uiShowOutputQuickActions)
                uiToggleButton("Speak Button (TTS)", keyPath: \.uiShowOutputSpeakButton)
                uiToggleButton("Diff Compare Button", keyPath: \.uiShowOutputDiffButton)
                uiToggleButton("In-Place Screen Overlay", keyPath: \.inPlaceOverlayEnabled)
            }
        } label: {
            Image(systemName: cfg.settings.minimalUIMode ? "line.3.horizontal.decrease.circle.fill" : "slider.horizontal.3")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundColor(cfg.settings.minimalUIMode ? .cyan : .white.opacity(0.9))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .foregroundStyle(.white)
                        .opacity(cfg.settings.minimalUIMode ? 0.22 : 0.14)
                )
        }
    }

    private func uiToggleButton(_ title: String, keyPath: WritableKeyPath<RuntimeSettings, Bool>) -> some View {
        let current = cfg.settings[keyPath: keyPath]
        return Button {
            cfg.updateUISettings { $0[keyPath: keyPath].toggle() }
        } label: {
            if current {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    var providerQuickMenu: some View {
        Menu {
            if !cfg.endpoints.isEmpty {
                Section("Switch Provider / Model") {
                    ForEach(cfg.endpoints) { ep in
                        let models = ep.effectiveModels
                        let isActiveProvider = ep.id == cfg.activatedEndpointID
                        if models.count > 1 {
                            Menu {
                                ForEach(models, id: \.self) { m in
                                    Button {
                                        switchToEndpoint(ep, model: m)
                                    } label: {
                                        if isActiveProvider && ep.model == m {
                                            Label(m, systemImage: "checkmark")
                                        } else {
                                            Text(m)
                                        }
                                    }
                                }
                            } label: {
                                if isActiveProvider {
                                    Label("\(ep.displayName) (\(ep.shortModelName))", systemImage: "checkmark")
                                } else {
                                    Text("\(ep.displayName) (\(models.count) models)")
                                }
                            }
                        } else {
                            Button {
                                switchToEndpoint(ep, model: nil)
                            } label: {
                                let label = "\(ep.displayName) — \(ep.model)"
                                if isActiveProvider {
                                    Label(label, systemImage: "checkmark")
                                } else {
                                    Text(label)
                                }
                            }
                        }
                    }
                }
                Divider()
            }
            Button {
                showQuickProviderSheet = true
            } label: {
                Label("Manage / Add Provider & Model...", systemImage: "slider.horizontal.3")
            }
        } label: {
            HStack(spacing: 3.5) {
                Image(systemName: cfg.activeEndpoint == nil ? "plus.circle.fill" : "cpu")
                    .font(.system(size: 10.5))
                Text(activeEndpointLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 96)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5))
                    .opacity(0.75)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.16))
            .clipShape(Capsule())
            .foregroundColor(.white)
        }
        .disabled(isRunning)
    }

    var screenOCRButton: some View {
        Button {
            launchScreenOCRFromHeader()
        } label: {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundColor(.cyan)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .foregroundStyle(.white)
                        .opacity(0.14)
                )
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
    }

    func resolveUnderlyingHostWindow() -> UIWindow? {
        if let win = context.targetView.window,
           win.windowLevel == .normal,
           !NSStringFromClass(type(of: win)).contains("WriteNow")
        {
            return win
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            if let win = ws.windows.first(where: {
                !$0.isHidden && $0.windowLevel == .normal && !NSStringFromClass(type(of: $0)).contains("WriteNow")
            }) {
                return win
            }
        }
        return nil
    }

    func launchScreenOCRFromHeader() {
        let hostWin = resolveUnderlyingHostWindow()
        if isRunning {
            stopStreaming()
        }
        dismiss()
        if let hostWin {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                ScreenPickerCoordinator.shared.presentPicker(in: hostWin, forceFullOCR: true)
            }
        }
    }

    func launchScreenRegionCapture() {
        let hostWin = resolveUnderlyingHostWindow()
        let preservedText = textProxy.selectedText
        let preservedImages = attachedImages
        if isRunning {
            stopStreaming()
        }
        dismiss()
        if let hostWin {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                ScreenPickerCoordinator.shared.presentRegionCapture(
                    in: hostWin,
                    existingText: preservedText,
                    existingImages: preservedImages,
                    mode: .attachImage
                )
            }
        }
    }

    var closeButton: some View {
        Image(systemName: "xmark")
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(.white)
            .opacity(isClosePressed ? 0.5 : 1)
            .frame(width: 26, height: 26)
            .background(
                Circle()
                    .foregroundStyle(.white)
                    .opacity(isClosePressed ? 0.08 : 0.16)
            )
            .animation(.easeOut(duration: 0.15), value: isClosePressed)
            ._onButtonGesture { isClosePressed = $0 } perform: {
                if isRunning {
                    stopStreaming()
                }
                dismiss()
            }
    }

    func switchToEndpoint(_ ep: EndpointItem, model: String?) {
        cfg.switchEndpoint(id: ep.id, model: model) { ok in
            if ok, shouldShowOutput, !isRunning, !isRetrying {
                executeCurrentTask()
            }
        }
    }
}

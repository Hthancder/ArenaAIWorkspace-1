//
//  WritingToolsView+Header.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

import SwiftUI

extension WritingToolsView {
    var selectedTextCount: Int {
        textProxy.selectedText.count
    }

    var textCountDescription: String {
        selectedTextCount > 1
            ? String(format: "%d characters".localized, selectedTextCount)
            : String(format: "%d character".localized, selectedTextCount)
    }

    var activeEndpointLabel: String {
        if let active = cfg.activeEndpoint {
            let shortModel = active.shortModelName
            if active.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return shortModel.isEmpty ? active.displayName : shortModel
            }
            return shortModel.isEmpty ? active.displayName : "\(active.displayName) · \(shortModel)"
        }
        return "Add Provider"
    }

    var title: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cfg.settings.menuTitle.isEmpty ? "Write Now".localized : cfg.settings.menuTitle)
                    .lineLimit(1)
                    .font(.headline.bold())
                Text(textCountDescription)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            providerQuickMenu

            closeButton
        }
        .onReceive(timer) { _ in
            if !isRunning {
                cfg.refreshRuntimeConfig()
            }
        }
    }

    var providerQuickMenu: some View {
        Menu {
            if let active = cfg.activeEndpoint, active.normalizedModels.count > 1 {
                Section("Models in \(active.displayName)") {
                    ForEach(active.normalizedModels, id: \.self) { m in
                        Button {
                            switchToEndpoint(active, model: m)
                        } label: {
                            if active.model == m {
                                Label(m, systemImage: "checkmark")
                            } else {
                                Text(m)
                            }
                        }
                    }
                }
                Divider()
            }

            if !cfg.endpoints.isEmpty {
                Section("Switch Provider") {
                    ForEach(cfg.endpoints) { ep in
                        let models = ep.normalizedModels
                        let isEPActive = ep.id == cfg.activatedEndpointID
                        if models.count > 1 {
                            Menu {
                                ForEach(models, id: \.self) { m in
                                    Button {
                                        switchToEndpoint(ep, model: m)
                                    } label: {
                                        if isEPActive && ep.model == m {
                                            Label(m, systemImage: "checkmark")
                                        } else {
                                            Text(m)
                                        }
                                    }
                                }
                            } label: {
                                let label = "\(ep.displayName) (\(models.count))"
                                if isEPActive {
                                    Label(label, systemImage: "checkmark")
                                } else {
                                    Text(label)
                                }
                            }
                        } else {
                            Button {
                                switchToEndpoint(ep, model: ep.model)
                            } label: {
                                let label = "\(ep.displayName) — \(ep.model)"
                                if isEPActive {
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
            HStack(spacing: 4) {
                Image(systemName: cfg.activeEndpoint == nil ? "plus.circle.fill" : "cpu")
                    .font(.caption2)
                Text(activeEndpointLabel)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .opacity(0.75)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.14))
            .clipShape(Capsule())
            .foregroundColor(.white)
        }
        .disabled(isRunning)
    }

    var closeButton: some View {
        Image(systemName: "xmark")
            .font(.footnote.bold())
            .foregroundStyle(.white)
            .opacity(isClosePressed ? 0.5 : 1)
            .frame(width: 26, height: 26)
            .background(
                Circle()
                    .foregroundStyle(.white)
                    .opacity(isClosePressed ? 0.08 : 0.14)
            )
            .animation(.easeOut(duration: 0.15), value: isClosePressed)
            ._onButtonGesture { isClosePressed = $0 } perform: {
                if isRunning {
                    stopStreaming()
                }
                dismiss()
            }
    }

    func switchToEndpoint(_ ep: EndpointItem, model: String? = nil) {
        cfg.switchEndpoint(id: ep.id, model: model) { ok in
            if ok, shouldShowOutput, !isRunning, !isRetrying {
                executeCurrentTask()
            }
        }
    }
}

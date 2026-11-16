//
//  WritingToolsView+Buttons.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

import Foundation
import SwiftUI

extension WritingToolsView {
    private var enabledPresets: [WritingPresetItem] {
        cfg.presets.filter(\.isEnabled)
    }

    private var gridColumns: [GridItem] {
        let count = cfg.settings.gridColumns == 3 ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: innerSpacing), count: count)
    }

    @ViewBuilder
    var selectiveButtonPanels: some View {
        VStack(spacing: innerSpacing) {
            // Quick custom prompt bar
            HStack(spacing: 6) {
                TextField("Ask AI anything (e.g. Translate to VI)...", text: $customPromptInput)
                    .font(.footnote)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(10)
                    .submitLabel(.send)
                    .onSubmit {
                        runCustomPrompt(customPromptInput)
                    }

                Button {
                    runCustomPrompt(customPromptInput)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundColor(customPromptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .white.opacity(0.35) : .white)
                }
                .disabled(customPromptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !cfg.settings.recentCustomPrompts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(cfg.settings.recentCustomPrompts, id: \.self) { recent in
                            Button {
                                runCustomPrompt(recent)
                            } label: {
                                Text(recent)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.12))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Dynamic preset grid
            ScrollView(showsIndicators: false) {
                if enabledPresets.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .opacity(0.6)
                        Text("No presets enabled. Use the quick prompt box above or manage presets in Settings.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .opacity(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: innerSpacing) {
                        ForEach(enabledPresets) { preset in
                            presetTile(preset)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
        .scaleEffect(initialAnimation * 0.15 + 0.85)
        .opacity(initialAnimation)
        .animation(.spring(), value: initialAnimation)
    }

    private func presetTile(_ preset: WritingPresetItem) -> some View {
        Button {
            currentTask = .preset(preset)
            executeCurrentTask()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: preset.icon.isEmpty ? "sparkles" : preset.icon)
                    .font(.body)
                Text(preset.localizedDisplayTitle)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !preset.outputLanguage.isEmpty || preset.insertBehavior == .append {
                    HStack(spacing: 4) {
                        if !preset.outputLanguage.isEmpty {
                            Text(preset.outputLanguage)
                        }
                        if preset.insertBehavior == .append {
                            Text("+Append")
                        }
                    }
                    .font(.system(size: 9))
                    .opacity(0.7)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .padding(.horizontal, 6)
            .background(Color.white.opacity(0.11))
            .cornerRadius(12)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    func runCustomPrompt(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cfg.recordQuickPrompt(trimmed)
        customPromptInput = ""
        currentTask = .customPrompt(trimmed)
        executeCurrentTask()
    }
}

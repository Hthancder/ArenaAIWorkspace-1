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
        cfg.presets.filter { preset in
            preset.isEnabled && preset.availability.matches(
                isReadOnly: textProxy.isReadOnly,
                showEditableInReadOnly: cfg.settings.readOnlyShowEditablePresets
            )
        }
    }

    private var enabledInputQuickActions: [RuntimeQuickActionItem] {
        cfg.settings.quickActions.filter { action in
            action.isEnabled
                && action.showOnInputPanel
                && !action.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && action.availability.matches(
                    isReadOnly: textProxy.isReadOnly,
                    showEditableInReadOnly: cfg.settings.readOnlyShowEditablePresets
                )
        }
    }

    private var gridColumns: [GridItem] {
        let count = cfg.settings.gridColumns == 3 ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: innerSpacing), count: count)
    }

    @ViewBuilder
    var selectiveButtonPanels: some View {
        if textProxy.isFetchingSelectedText && context.launchSlotAction != nil {
            VStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                Text("Reading selected text...")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            selectiveButtonPanelsBody
        }
    }

    @ViewBuilder
    private var selectiveButtonPanelsBody: some View {
        VStack(spacing: innerSpacing) {
            let trimmedInput = textProxy.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedInput.isEmpty {
                Button {
                    showSelectedTextPreviewAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: textProxy.isReadOnly ? "doc.text.viewfinder" : "text.quote")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.72))
                        Text(trimmedInput.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.76))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(trimmedInput.count)c")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
            }

            // Quick custom prompt + Voice bar
            HStack(spacing: 6) {
                if (isRecordingVoice || isProcessingVoice) && !voiceTargetIsFollowUp {
                    liveRecordingStrip
                } else {
                    TextField(
                        selectedPresetForCustomPrompt != nil
                            ? "Custom instruction for \(selectedPresetForCustomPrompt!.localizedDisplayTitle)..."
                            : (voiceMode == "dictate"
                                ? "Tap or hold Mic to dictate..."
                                : (voiceMode == "translate"
                                    ? "Tap or hold Mic to speak & translate..."
                                    : (textProxy.isReadOnly ? "Ask, translate, or prompt freely..." : "Ask AI anything or hold Mic..."))),
                        text: $customPromptInput
                    )
                    .font(.footnote)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(10)
                    .submitLabel(.send)
                    .onSubmit {
                        runCustomPrompt(customPromptInput)
                    }
                }

                if !(isRecordingVoice || isProcessingVoice) {
                    attachmentMenuButton
                }

                if !(isRecordingVoice || isProcessingVoice), !enabledPresets.isEmpty {
                    Menu {
                        if selectedPresetForCustomPrompt != nil {
                            Button(role: .destructive) {
                                selectedPresetForCustomPrompt = nil
                            } label: {
                                Label("Clear Attached Preset", systemImage: "xmark.circle")
                            }
                            Divider()
                        }
                        ForEach(enabledPresets) { preset in
                            Button {
                                selectedPresetForCustomPrompt = preset
                            } label: {
                                Label(
                                    preset.localizedDisplayTitle,
                                    systemImage: selectedPresetForCustomPrompt?.id == preset.id ? "checkmark.circle.fill" : (preset.icon.isEmpty ? "sparkles" : preset.icon)
                                )
                            }
                        }
                    } label: {
                        Image(systemName: selectedPresetForCustomPrompt != nil ? "link.circle.fill" : "plus.circle")
                            .font(.title3)
                            .foregroundColor(selectedPresetForCustomPrompt != nil ? .cyan : .white.opacity(0.75))
                    }
                }

                if cfg.settings.stt.enabled {
                    makeMicButton(isFollowUp: false)
                }

                if !(isRecordingVoice || isProcessingVoice) {
                    let hasPromptOrAttachments = !customPromptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !attachedImages.isEmpty
                        || !attachedFiles.isEmpty
                    Button {
                        runCustomPromptOrAttachmentFallback()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundColor(hasPromptOrAttachments ? .white : .white.opacity(0.35))
                    }
                    .disabled(!hasPromptOrAttachments)
                }
            }

            if !attachedImages.isEmpty || !attachedFiles.isEmpty {
                attachmentsStrip
            }

            if !attachmentBannerMessage.isEmpty {
                attachmentBannerView
            }

            if let attachedPreset = selectedPresetForCustomPrompt {
                HStack(spacing: 6) {
                    Image(systemName: attachedPreset.icon.isEmpty ? "sparkles" : attachedPreset.icon)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.cyan)
                    Text("Preset + Prompt: \(attachedPreset.localizedDisplayTitle)")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    if !attachedPreset.outputLanguage.isEmpty {
                        Text("· \(attachedPreset.outputLanguage)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button {
                        selectedPresetForCustomPrompt = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.cyan.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.cyan.opacity(0.45), lineWidth: 1)
                )
                .cornerRadius(8)
            }

            if cfg.settings.stt.enabled {
                voiceModeAndLanguageStrip
            }

            if cfg.settings.keepEditContextEnabled, let prior = activePriorEditContext {
                HStack(spacing: 6) {
                    Button {
                        priorEditContextAttached.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: priorEditContextAttached ? "brain.head.profile" : "brain")
                                .font(.caption2)
                            let n = prior.turns.count
                            Text(priorEditContextAttached
                                ? "Edit Memory (\(n) \(n == 1 ? "step" : "steps")) ✓"
                                : "Attach Edit Memory (\(n))")
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(priorEditContextAttached ? Color.purple.opacity(0.36) : Color.white.opacity(0.12))
                        .cornerRadius(7)
                    }
                    .buttonStyle(.plain)

                    if let lastStep = prior.turns.last {
                        Button {
                            showEditMemoryAlert = true
                        } label: {
                            HStack(spacing: 3) {
                                Text(lastStep.instruction)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.68))
                                    .lineLimit(1)
                                Image(systemName: "info.circle")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 2)

                    Button {
                        activePriorEditContext = nil
                        priorEditContextAttached = false
                        cfg.clearEditContext()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let snapshot = restorableSession {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.cyan)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Restore: \(snapshot.taskTitle)")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                        Text(snapshot.output)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.68))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Button("Restore") {
                        restoreLastSession(snapshot)
                    }
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.32))
                    .cornerRadius(6)
                    .buttonStyle(.plain)

                    Button {
                        restorableSession = nil
                        cfg.clearLastSession()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.11))
                .cornerRadius(9)
            }

            if (isNotificationContext || cfg.settings.clipboardContextEnabled), !clipboardContextText.isEmpty {
                HStack(spacing: 6) {
                    Button {
                        clipboardContextAttached.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isNotificationContext
                                ? (clipboardContextAttached ? "bell.badge.fill" : "bell")
                                : (clipboardContextAttached ? "doc.on.clipboard.fill" : "doc.on.clipboard"))
                                .font(.caption2)
                            Text(isNotificationContext
                                ? (clipboardContextAttached ? "Notification ✓" : "+ Notification")
                                : (clipboardContextAttached ? "Clipboard ✓" : "+ Clipboard"))
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(clipboardContextAttached ? Color.green.opacity(0.32) : Color.white.opacity(0.12))
                        .cornerRadius(7)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showContextPreviewAlert = true
                    } label: {
                        Text(clipboardContextText.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.68))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 2)

                    Button {
                        runSmartReply()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .font(.system(size: 9))
                            Text("Smart Reply")
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.20))
                        .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !voiceBannerMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                    Text(voiceBannerMessage)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                    Spacer()
                    Button {
                        voiceBannerMessage = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.28))
                .cornerRadius(8)
            }

            if !enabledInputQuickActions.isEmpty {
                ResponsiveHorizontalScrollView {
                    HStack(spacing: 6) {
                        ForEach(enabledInputQuickActions) { action in
                            Button {
                                runCustomPrompt(action.instruction)
                            } label: {
                                HStack(spacing: 4) {
                                    if !action.icon.isEmpty {
                                        Image(systemName: action.icon)
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    Text(action.title)
                                        .font(.caption2.weight(.semibold))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.16))
                                .cornerRadius(8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundColor(.white)
                }
                .frame(height: 28)
            }

            if !cfg.settings.recentCustomPrompts.isEmpty {
                ResponsiveHorizontalScrollView {
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
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundColor(.white)
                }
                .frame(height: 26)
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
        let pendingPrompt = customPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCombinedReady = !pendingPrompt.isEmpty
        let isAttached = selectedPresetForCustomPrompt?.id == preset.id

        return Button {
            if !pendingPrompt.isEmpty {
                runPresetWithPrompt(preset, instruction: pendingPrompt)
            } else {
                selectedPresetForCustomPrompt = nil
                currentTask = .preset(preset)
                executeCurrentTask()
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: preset.icon.isEmpty ? "sparkles" : preset.icon)
                    .font(.body)
                Text(preset.localizedDisplayTitle)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if isCombinedReady {
                    Text("+ Prompt")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.cyan)
                        .lineLimit(1)
                } else if !preset.outputLanguage.isEmpty || preset.insertBehavior == .append || !preset.shortOverrideModelName.isEmpty || preset.availability == .readOnlyOnly {
                    HStack(spacing: 4) {
                        if preset.availability == .readOnlyOnly {
                            Text("Read")
                        }
                        if !preset.shortOverrideModelName.isEmpty {
                            Text(preset.shortOverrideModelName)
                        }
                        if !preset.outputLanguage.isEmpty {
                            Text(preset.outputLanguage)
                        }
                        if preset.insertBehavior == .append && !textProxy.isReadOnly {
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
            .background(isAttached ? Color.cyan.opacity(0.24) : Color.white.opacity(0.11))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isAttached || isCombinedReady ? Color.cyan.opacity(isAttached ? 0.65 : 0.35) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(12)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isCombinedReady {
                Button {
                    runPresetWithPrompt(preset, instruction: pendingPrompt)
                } label: {
                    Label("Combine Preset + Prompt", systemImage: "link.badge.plus")
                }
            }
            Button {
                selectedPresetForCustomPrompt = preset
            } label: {
                Label("Attach to Custom Prompt", systemImage: "link")
            }
            Button {
                currentTask = .preset(preset)
                executeCurrentTask()
            } label: {
                Label("Run Preset Only", systemImage: "play.fill")
            }
        }
    }

    func runPresetWithPrompt(_ preset: WritingPresetItem, instruction raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            currentTask = .preset(preset)
            executeCurrentTask()
            return
        }
        cfg.recordQuickPrompt(trimmed)
        customPromptInput = ""
        selectedPresetForCustomPrompt = nil
        currentTask = .presetWithPrompt(preset, instruction: trimmed)
        executeCurrentTask()
    }

    func runCustomPromptOrAttachmentFallback() {
        let trimmed = customPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            runCustomPrompt(trimmed)
        } else if !attachedImages.isEmpty || !attachedFiles.isEmpty {
            let fallbackPrompt = "Analyze, summarize, and explain the attached content clearly."
            if let attachedPreset = selectedPresetForCustomPrompt {
                runPresetWithPrompt(attachedPreset, instruction: fallbackPrompt)
            } else {
                currentTask = .customPrompt(fallbackPrompt)
                executeCurrentTask()
            }
        }
    }

    func runCustomPrompt(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let attachedPreset = selectedPresetForCustomPrompt {
            runPresetWithPrompt(attachedPreset, instruction: trimmed)
            return
        }
        cfg.recordQuickPrompt(trimmed)
        customPromptInput = ""
        currentTask = .customPrompt(trimmed)
        executeCurrentTask()
    }

    // MARK: - Attachment UI & Actions

    @ViewBuilder
    var attachmentMenuButton: some View {
        let count = attachedImages.count + attachedFiles.count
        Menu {
            Button {
                pickPhotos()
            } label: {
                Label("Attach Photo".localized, systemImage: "photo.on.rectangle.angled")
            }

            Button {
                attachScreenShot()
            } label: {
                Label("Capture Screen".localized, systemImage: "camera.viewfinder")
            }

            Button {
                pasteClipboardImage()
            } label: {
                Label("Paste Image".localized, systemImage: "doc.on.clipboard")
            }

            Button {
                pickFiles()
            } label: {
                Label("Attach File".localized, systemImage: "doc.badge.plus")
            }

            Divider()

            Button {
                ocrTextFromPhoto()
            } label: {
                Label("OCR Text from Photo".localized, systemImage: "text.viewfinder")
            }

            if cfg.settings.readOnlyEnabled {
                Button {
                    launchScreenOCRFromHeader()
                } label: {
                    Label("Screen OCR".localized, systemImage: "viewfinder")
                }
            }

            if count > 0 {
                Divider()
                Button(role: .destructive) {
                    attachedImages.removeAll()
                    attachedFiles.removeAll()
                    attachmentBannerMessage = ""
                } label: {
                    Label("Clear Attachments".localized, systemImage: "trash")
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: count > 0 ? "paperclip.circle.fill" : "paperclip.circle")
                    .font(.title3)
                    .foregroundColor(count > 0 ? .cyan : .white.opacity(0.75))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1)
                        .background(Color.cyan)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -3)
                }
            }
        }
    }

    @ViewBuilder
    var attachmentsStrip: some View {
        ResponsiveHorizontalScrollView {
            HStack(spacing: 6) {
                ForEach(attachedImages) { item in
                    ZStack(alignment: .topTrailing) {
                        HStack(spacing: 5) {
                            Image(uiImage: item.thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 26, height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.label)
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                                Text(item.sizeSummary)
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.65))
                            }
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 18)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.cyan.opacity(0.45), lineWidth: 0.8)
                        )
                        .cornerRadius(8)

                        Button {
                            attachedImages.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .padding(3)
                    }
                }

                ForEach(attachedFiles) { file in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            previewAttachedFile = file
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: file.fileExtension == "pdf" ? "doc.richtext" : "doc.text.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(file.fileName)
                                        .font(.system(size: 10, weight: .semibold))
                                        .lineLimit(1)
                                    Text(file.isTruncated ? "\(file.charCountSummary)+" : file.charCountSummary)
                                        .font(.system(size: 8.5, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.65))
                                }
                            }
                            .padding(.leading, 7)
                            .padding(.trailing, 20)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.20))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.45), lineWidth: 0.8)
                            )
                            .cornerRadius(8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            attachedFiles.removeAll { $0.id == file.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .padding(3)
                    }
                }
            }
            .foregroundColor(.white)
        }
        .frame(height: 36)
    }

    @ViewBuilder
    var attachmentBannerView: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.caption2)
                .foregroundColor(.cyan)
            Text(attachmentBannerMessage)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(2)
            Spacer()
            Button {
                attachmentBannerMessage = ""
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.65))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.28))
        .cornerRadius(8)
    }

    func pickPhotos() {
        let remaining = max(1, 4 - attachedImages.count)
        AttachmentPickerHelper.presentPhotoPicker(from: context, remainingSlots: remaining) { items in
            guard !items.isEmpty else { return }
            for item in items {
                if attachedImages.count < 4 {
                    attachedImages.append(item)
                }
            }
            attachmentBannerMessage = ""
        }
    }

    func pickFiles() {
        AttachmentPickerHelper.presentDocumentPicker(from: context) { images, files, errors in
            for img in images where attachedImages.count < 4 {
                attachedImages.append(img)
            }
            for file in files where attachedFiles.count < 4 {
                attachedFiles.append(file)
            }
            if let firstErr = errors.first {
                attachmentBannerMessage = firstErr
            } else {
                attachmentBannerMessage = ""
            }
        }
    }

    func attachScreenShot() {
        guard attachedImages.count < 4 else {
            attachmentBannerMessage = "Max 4 images attached."
            return
        }
        AttachmentPickerHelper.captureScreenSnapshot(from: context) { item in
            if let item {
                attachedImages.append(item)
                attachmentBannerMessage = ""
            } else {
                attachmentBannerMessage = "Could not capture screen snapshot."
            }
        }
    }

    func ocrTextFromPhoto() {
        let langs = cfg.settings.ocrPreferredLanguages
        AttachmentPickerHelper.presentPhotoOCRPicker(from: context, preferredLanguages: langs) { extracted in
            let trimmed = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                attachmentBannerMessage = "No text detected in photo.".localized
                return
            }
            attachmentBannerMessage = ""
            if shouldShowOutput {
                if followUpPromptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    followUpPromptInput = trimmed
                } else {
                    followUpPromptInput += "\n\n" + trimmed
                }
            } else {
                if customPromptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    customPromptInput = trimmed
                } else {
                    customPromptInput += "\n\n" + trimmed
                }
            }
        }
    }

    func pasteClipboardImage() {
        guard attachedImages.count < 4 else {
            attachmentBannerMessage = "Max 4 images attached."
            return
        }
        if let img = UIPasteboard.general.image,
           let item = AttachedImageItem.fromUIImage(img, label: "Clipboard")
        {
            attachedImages.append(item)
            attachmentBannerMessage = ""
        } else {
            attachmentBannerMessage = "No image in clipboard".localized
        }
    }

    func runSmartReply() {
        if !clipboardContextText.isEmpty {
            clipboardContextAttached = true
            let draftNote = textProxy.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let instruction = draftNote.isEmpty
                ? "Write a natural, helpful, ready-to-send reply to the clipboard message in the same language as that message."
                : "Write a natural, ready-to-send reply to the clipboard message incorporating my draft notes/points in the selected text."
            currentTask = .customPrompt(instruction)
        } else {
            currentTask = .customPrompt("Write a natural, clear, ready-to-send reply to the selected message in the same language.")
        }
        executeCurrentTask()
    }

    func restoreLastSession(_ snapshot: LastSessionSnapshot) {
        output = snapshot.output
        outputHistory = snapshot.outputHistory.isEmpty ? [snapshot.output] : snapshot.outputHistory
        historyIndex = max(0, min(snapshot.historyIndex, outputHistory.count - 1))
        voiceLastTranscript = snapshot.voiceLastTranscript
        isEditingOutput = false
        diffDisplayMode = .none
        restorableSession = nil
    }
}

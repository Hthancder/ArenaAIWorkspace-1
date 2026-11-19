//
//  WritingToolsView.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

import SwiftUI
import UIKit

enum OutputDiffDisplayMode: Equatable {
    case none
    case wordDiff
    case originalSplit
}

struct WritingToolsView: View {
    @ObservedObject var cfg = Configurator.shared
    @StateObject var context: Presenter.Context
    @StateObject var textProxy: TextProxy

    @Environment(\.dismiss) var dismiss

    @State var isRunning: Bool = false

    @State var isRetrying: Bool = false
    @State var shouldRetryWhenActive: Bool = false

    @State var output: String = ""
    @State var outputHistory: [String] = []
    @State var historyIndex: Int = 0
    @State var currentTask: WritingTaskKind = .preset(WritingPresetItem.defaultPresets[1])

    @State var customPromptInput: String = ""
    @State var selectedPresetForCustomPrompt: WritingPresetItem? = nil
    @State var lastPresetForFollowUp: WritingPresetItem? = nil
    @State var followUpPromptInput: String = ""
    @State var isEditingOutput: Bool = false
    @State var diffDisplayMode: OutputDiffDisplayMode = .none
    @State var copiedToast: Bool = false
    @State var showQuickProviderSheet: Bool = false
    @State var showEditMemoryAlert: Bool = false
    @State var showContextPreviewAlert: Bool = false
    @State var showSelectedTextPreviewAlert: Bool = false
    @State var requestStartedAt: Date? = nil
    @State var lastGenerationDuration: TimeInterval? = nil
    @State var isSpeakingOutput: Bool = false
    @State var didTriggerLaunchAction: Bool = false

    // Clipboard Context, Session Restore & Previous-Edit Context
    @State var clipboardContextText: String = ""
    @State var clipboardContextAttached: Bool = false
    @State var isNotificationContext: Bool = false
    @State var restorableSession: LastSessionSnapshot? = nil
    @State var activePriorEditContext: EditContextRecord? = nil
    @State var priorEditContextAttached: Bool = false
    @State var currentSessionTurns: [EditContextTurn] = []

    // Multimodal Image & File Attachments
    @State var attachedImages: [AttachedImageItem] = []
    @State var attachedFiles: [AttachedFileItem] = []
    @State var attachmentBannerMessage: String = ""
    @State var previewAttachedFile: AttachedFileItem? = nil

    @State var error: Error? = nil
    @State var activeRequestToken: UUID = UUID()

    // Voice / STT state
    @State var isRecordingVoice: Bool = false
    @State var isProcessingVoice: Bool = false
    @State var voiceHoldActive: Bool = false
    @State var voiceSlideWillCancel: Bool = false
    @State var voiceTargetIsFollowUp: Bool = false
    @State var voiceDuration: Double = 0
    @State var voiceLevel: Double = 0
    @State var voiceLevelHistory: [CGFloat] = Array(repeating: 0.12, count: 18)
    @State var voiceMode: String = Configurator.shared.settings.stt.voiceMode
    @State var voiceSourceLang: String = Configurator.shared.settings.stt.sourceLanguage
    @State var voiceTargetLang: String = Configurator.shared.settings.stt.targetLanguage
    @State var voiceLastTranscript: String = ""
    @State var voiceBannerMessage: String = ""
    @State var voicePollTimer: Timer? = nil

    @State var initialAnimation: CGFloat = 0
    @State var isClosePressed: Bool = false
    @State var isPopoverExpanded: Bool = Configurator.shared.settings.popoverSizePreset == "expanded"

    var shouldShowError: Bool {
        error != nil
    }

    var shouldShowOutput: Bool {
        isRunning || !output.isEmpty
    }

    var shouldShowSelectiveButtons: Bool {
        !shouldShowError && !shouldShowOutput
    }

    var activeClipboardContext: String? {
        guard isNotificationContext || cfg.settings.clipboardContextEnabled, clipboardContextAttached else { return nil }
        let trimmed = clipboardContextText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var effectivePriorEditContext: EditContextRecord? {
        guard cfg.settings.keepEditContextEnabled, priorEditContextAttached else { return nil }
        return activePriorEditContext
    }

    var currentTaskInstructionLabel: String {
        switch currentTask {
        case let .preset(preset): return preset.title
        case let .presetWithPrompt(preset, prompt): return "\(preset.title): \(prompt)"
        case let .customPrompt(prompt): return prompt
        case let .followUp(_, _, instruction): return instruction
        }
    }

    var currentTaskTitle: String {
        switch currentTask {
        case let .preset(preset): return preset.localizedDisplayTitle
        case let .presetWithPrompt(preset, prompt): return "\(preset.localizedDisplayTitle) + \(String(prompt.prefix(20)))"
        case let .customPrompt(prompt): return String(prompt.prefix(32))
        case .followUp: return "Refined Draft"
        }
    }

    let spacing: CGFloat = 12
    let innerSpacing: CGFloat = 8

    init(context: Presenter.Context) {
        _context = .init(wrappedValue: context)
        _textProxy = .init(wrappedValue: context.textProxy)
    }

    public var body: some View {
        VStack(spacing: 12) {
            title
            if shouldShowError {
                errorView
            } else if shouldShowOutput {
                outputPanel
            } else {
                selectiveButtonPanels
            }
        }
        .animation(.spring(), value: isRunning)
        .animation(.easeInOut(duration: 0.2), value: error?.localizedDescription)
        .animation(.easeInOut(duration: 0.2), value: isEditingOutput)
        .animation(.easeInOut(duration: 0.2), value: diffDisplayMode)
        .padding(14)
        .background(background)
        .foregroundStyle(.white)
        .sheet(isPresented: $showQuickProviderSheet) {
            QuickProviderSheet()
        }
        .alert("Edit Memory", isPresented: $showEditMemoryAlert) {
            Button("Clear Memory", role: .destructive) {
                activePriorEditContext = nil
                priorEditContextAttached = false
                cfg.clearEditContext()
            }
            Button("OK", role: .cancel) {}
        } message: {
            if let prior = activePriorEditContext {
                let steps = prior.turns.enumerated().map { idx, t in
                    "• Step \(idx + 1) [\(t.instruction)]:\n\(String(t.output.prefix(160)))"
                }.joined(separator: "\n")
                Text("Original:\n\(String(prior.originalText.prefix(240)))\n\n\(steps)")
            } else {
                Text("No previous edit history attached.")
            }
        }
        .alert(isNotificationContext ? "Notification Context" : "Clipboard Context", isPresented: $showContextPreviewAlert) {
            Button(clipboardContextAttached ? "Detach" : "Attach") {
                clipboardContextAttached.toggle()
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(clipboardContextText.prefix(700)))
        }
        .alert("Captured Input Text", isPresented: $showSelectedTextPreviewAlert) {
            Button("Copy") {
                UIPasteboard.general.string = textProxy.selectedText
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(textProxy.selectedText.prefix(900)))
        }
        .alert(
            previewAttachedFile?.fileName ?? "Attached File",
            isPresented: Binding(
                get: { previewAttachedFile != nil },
                set: { if !$0 { previewAttachedFile = nil } }
            )
        ) {
            if let file = previewAttachedFile {
                Button("Remove", role: .destructive) {
                    attachedFiles.removeAll { $0.id == file.id }
                    previewAttachedFile = nil
                }
            }
            Button("OK", role: .cancel) {
                previewAttachedFile = nil
            }
        } message: {
            if let file = previewAttachedFile {
                Text(String(file.extractedText.prefix(900)))
            }
        }
        .onAppear {
            initialAnimation = 1
            if attachedImages.isEmpty && !context.initialAttachedImages.isEmpty {
                attachedImages = context.initialAttachedImages
            }
            voiceMode = cfg.settings.stt.voiceMode
            voiceSourceLang = cfg.settings.stt.sourceLanguage
            voiceTargetLang = cfg.settings.stt.targetLanguage
            refreshClipboardAndSessionState()
            maybeTriggerLaunchAction()
            cfg.refreshRuntimeConfig { updated in
                if let updated {
                    voiceMode = updated.settings.stt.voiceMode
                    voiceSourceLang = updated.settings.stt.sourceLanguage
                    voiceTargetLang = updated.settings.stt.targetLanguage
                    refreshClipboardAndSessionState()
                }
            }
        }
        .onChange(of: textProxy.isFetchingSelectedText) { fetching in
            if !fetching {
                refreshEditContextMatch()
                maybeTriggerLaunchAction()
            }
        }
        .onDisappear {
            voicePollTimer?.invalidate()
            voicePollTimer = nil
            OutputSpeechHelper.shared.stop()
            isSpeakingOutput = false
            if isRecordingVoice {
                cfg.cancelVoiceRecording()
            }
            if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cfg.saveLastSession(
                    output: output,
                    outputHistory: outputHistory,
                    historyIndex: historyIndex,
                    taskTitle: currentTaskTitle,
                    voiceLastTranscript: voiceLastTranscript
                )
            }
        }
        .onChange(of: context.scenePhase) { phase in
            switch phase {
            case .active:
                if shouldRetryWhenActive {
                    error = nil
                    isRetrying = true
                    shouldRetryWhenActive = false
                    executeCurrentTask(delayedForRetry: true)
                }
            default:
                break
            }
        }
    }

    private func refreshClipboardAndSessionState() {
        let notifCtx = (context.prefetchedExternalContext ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !notifCtx.isEmpty {
            clipboardContextText = String(notifCtx.prefix(3000))
            isNotificationContext = true
            if textProxy.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clipboardContextAttached = true
            }
        } else if cfg.settings.clipboardContextEnabled {
            isNotificationContext = false
            let rawClip = (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawClip.isEmpty {
                clipboardContextText = String(rawClip.prefix(3000))
                if cfg.settings.autoAttachClipboardOnEmpty,
                   textProxy.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    clipboardContextAttached = true
                }
            } else {
                clipboardContextText = ""
                clipboardContextAttached = false
            }
        } else {
            isNotificationContext = false
            clipboardContextText = ""
            clipboardContextAttached = false
        }

        restorableSession = cfg.loadValidLastSession()
        refreshEditContextMatch()
    }

    private func refreshEditContextMatch() {
        guard !textProxy.isFetchingSelectedText else { return }
        if let matched = cfg.loadMatchingEditContext(forSelectedText: textProxy.selectedText) {
            activePriorEditContext = matched
            priorEditContextAttached = true
        } else if !cfg.settings.keepEditContextEnabled {
            activePriorEditContext = nil
            priorEditContextAttached = false
        }
    }

    private func maybeTriggerLaunchAction() {
        guard !didTriggerLaunchAction,
              !textProxy.isFetchingSelectedText,
              let launch = context.launchSlotAction
        else { return }
        didTriggerLaunchAction = true

        let hasText = !textProxy.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasExtraSlotPrompt = !launch.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasText && ((launch.actionKind == .preset && !hasExtraSlotPrompt) || launch.actionKind == .customPrompt) {
            // Avoid sending empty selected text automatically on slot launch if WebKit/view returned nothing
            return
        }

        switch launch.actionKind {
        case .preset:
            if let pid = launch.presetID,
               let preset = cfg.presets.first(where: { $0.id == pid })
            {
                let extra = launch.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if extra.isEmpty {
                    currentTask = .preset(preset)
                } else {
                    currentTask = .presetWithPrompt(preset, instruction: extra)
                }
                executeCurrentTask()
            } else {
                let fallback = launch.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                runCustomPrompt(fallback.isEmpty ? launch.title : fallback)
            }
        case .customPrompt:
            let promptText = launch.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            runCustomPrompt(promptText.isEmpty ? launch.title : promptText)
        case .smartReply:
            runSmartReply()
        case .voicePrompt:
            if cfg.settings.stt.enabled {
                beginVoiceCapture(isFollowUp: false)
            }
        }
    }
}

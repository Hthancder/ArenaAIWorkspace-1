//
//  WritingToolsView.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

import SwiftUI

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
    @State var followUpPromptInput: String = ""
    @State var isEditingOutput: Bool = false
    @State var showOriginalDiff: Bool = false
    @State var copiedToast: Bool = false
    @State var showQuickProviderSheet: Bool = false

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

    var shouldShowError: Bool {
        error != nil
    }

    var shouldShowOutput: Bool {
        isRunning || !output.isEmpty
    }

    var shouldShowSelectiveButtons: Bool {
        !shouldShowError && !shouldShowOutput
    }

    let spacing: CGFloat = 12
    let innerSpacing: CGFloat = 8

    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

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
        .animation(.easeInOut(duration: 0.2), value: showOriginalDiff)
        .padding(14)
        .background(background)
        .foregroundStyle(.white)
        .sheet(isPresented: $showQuickProviderSheet) {
            QuickProviderSheet()
        }
        .onAppear {
            initialAnimation = 1
            voiceMode = cfg.settings.stt.voiceMode
            voiceSourceLang = cfg.settings.stt.sourceLanguage
            voiceTargetLang = cfg.settings.stt.targetLanguage
            cfg.refreshRuntimeConfig { updated in
                if let updated {
                    voiceMode = updated.settings.stt.voiceMode
                    voiceSourceLang = updated.settings.stt.sourceLanguage
                    voiceTargetLang = updated.settings.stt.targetLanguage
                }
            }
        }
        .onDisappear {
            voicePollTimer?.invalidate()
            voicePollTimer = nil
            if isRecordingVoice {
                cfg.cancelVoiceRecording()
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
}

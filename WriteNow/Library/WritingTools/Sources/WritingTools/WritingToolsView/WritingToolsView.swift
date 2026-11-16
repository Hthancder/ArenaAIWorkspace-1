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
            cfg.refreshRuntimeConfig()
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

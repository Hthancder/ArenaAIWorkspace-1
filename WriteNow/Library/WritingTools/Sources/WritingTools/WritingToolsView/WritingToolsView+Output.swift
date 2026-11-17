//
//  WritingToolsView+Output.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

extension WritingToolsView {
    private var enabledOutputQuickActions: [RuntimeQuickActionItem] {
        cfg.settings.quickActions.filter { action in
            action.isEnabled
                && action.showOnOutputRefine
                && !action.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && action.availability.matches(
                    isReadOnly: textProxy.isReadOnly,
                    showEditableInReadOnly: cfg.settings.readOnlyShowEditablePresets
                )
        }
    }

    var outputPanel: some View {
        VStack(spacing: 8) {
            // Top mini-toolbar: version history, Original compare, Manual Edit, Speak, Memory
            if !output.isEmpty || outputHistory.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if outputHistory.count > 1 {
                            HStack(spacing: 4) {
                                Button {
                                    navigateHistory(delta: -1)
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.caption.bold())
                                }
                                .disabled(historyIndex <= 0 || isRunning)

                                Text("\(historyIndex + 1)/\(outputHistory.count)")
                                    .font(.caption2.monospacedDigit())

                                Button {
                                    navigateHistory(delta: 1)
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                }
                                .disabled(historyIndex >= outputHistory.count - 1 || isRunning)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(8)
                        }

                        if cfg.settings.keepEditContextEnabled, let prior = activePriorEditContext {
                            Button {
                                priorEditContextAttached.toggle()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 9))
                                    Text(priorEditContextAttached ? "Memory (\(prior.turns.count))" : "Memory Off")
                                        .font(.caption2.weight(.medium))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(priorEditContextAttached ? Color.purple.opacity(0.34) : Color.white.opacity(0.10))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(isRunning)
                        }

                        if cfg.settings.wordDiffEnabled && !textProxy.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                diffDisplayMode = (diffDisplayMode == .wordDiff) ? .none : .wordDiff
                                if diffDisplayMode != .none { isEditingOutput = false }
                            } label: {
                                Label("Diff", systemImage: "doc.text.magnifyingglass")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(diffDisplayMode == .wordDiff ? Color.white.opacity(0.28) : Color.white.opacity(0.12))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(isRunning)
                        }

                        Button {
                            diffDisplayMode = (diffDisplayMode == .originalSplit) ? .none : .originalSplit
                            if diffDisplayMode != .none { isEditingOutput = false }
                        } label: {
                            Label("Original".localized, systemImage: diffDisplayMode == .originalSplit ? "eye.fill" : "eye")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(diffDisplayMode == .originalSplit ? Color.white.opacity(0.28) : Color.white.opacity(0.12))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button {
                            if isEditingOutput, outputHistory.indices.contains(historyIndex) {
                                outputHistory[historyIndex] = output
                            }
                            isEditingOutput.toggle()
                            if isEditingOutput { diffDisplayMode = .none }
                        } label: {
                            Label(isEditingOutput ? "Done".localized : "Edit".localized, systemImage: isEditingOutput ? "checkmark" : "pencil")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isEditingOutput ? Color.white.opacity(0.28) : Color.white.opacity(0.12))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(isRunning)

                        if cfg.settings.readOnlyShowSpeakButton && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                toggleSpeakOutput()
                            } label: {
                                Image(systemName: isSpeakingOutput ? "stop.circle.fill" : "speaker.wave.2")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(isSpeakingOutput ? Color.cyan.opacity(0.32) : Color.white.opacity(0.12))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(isRunning)
                        }
                    }
                }
            }

            // Content area
            if isRunning, output.isEmpty {
                ProgressView()
                    .tint(.white)
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else if isEditingOutput {
                EditableOutputTextView(text: $output)
                    .padding(8)
                    .background(Color.white.opacity(0.10))
                    .cornerRadius(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StickToBottomScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !voiceLastTranscript.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SPOKEN (\(WritingVoiceLanguageCatalog.shortLabel(for: voiceSourceLang)))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.55))
                                Text(voiceLastTranscript)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.78))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                        }

                        if diffDisplayMode == .originalSplit {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ORIGINAL")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.55))
                                Text(textProxy.selectedText)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.75))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                        }

                        if diffDisplayMode == .wordDiff && !isRunning {
                            WordLevelDiffView(original: textProxy.selectedText, updated: output)
                        } else {
                            Text(output)
                                .multilineTextAlignment(.leading)
                                .font(.system(.footnote))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider().hidden()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            // Inline refine chips + follow-up prompt input (when idle with output)
            if !isRunning, !output.isEmpty {
                VStack(spacing: 6) {
                    if !enabledOutputQuickActions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(enabledOutputQuickActions) { chip in
                                    Button {
                                        runFollowUp(chip.instruction)
                                    } label: {
                                        HStack(spacing: 3) {
                                            if !chip.icon.isEmpty {
                                                Image(systemName: chip.icon)
                                                    .font(.system(size: 9))
                                            }
                                            Text(chip.title)
                                                .font(.caption2.weight(.medium))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.13))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
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

                    HStack(spacing: 6) {
                        if (isRecordingVoice || isProcessingVoice) && voiceTargetIsFollowUp {
                            liveRecordingStrip
                        } else {
                            TextField(
                                textProxy.isReadOnly ? "Ask a follow-up or hold Mic..." : "Refine result or hold Mic...",
                                text: $followUpPromptInput
                            )
                                .font(.caption)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(9)
                                .submitLabel(.send)
                                .onSubmit {
                                    runFollowUp(followUpPromptInput)
                                }
                        }

                        if cfg.settings.stt.enabled {
                            makeMicButton(isFollowUp: true)
                        }

                        if !(isRecordingVoice || isProcessingVoice) {
                            Button {
                                runFollowUp(followUpPromptInput)
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(followUpPromptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .white.opacity(0.35) : .white)
                            }
                            .disabled(followUpPromptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }

            // Bottom Action Bar
            if isRunning {
                HStack(spacing: innerSpacing) {
                    BeautifulButton(title: "Discard".localized) { discard() }
                    BeautifulButton(title: "Stop".localized) { stopStreaming() }
                }
                .frame(height: 38)
            } else if textProxy.isReadOnly {
                readOnlyActionBar
                    .frame(height: 38)
            } else {
                HStack(spacing: 6) {
                    BeautifulButton(title: "Discard".localized) { discard() }
                    BeautifulButton(title: "Again".localized) { executeCurrentTask() }
                    BeautifulButton(title: copiedToast ? "Copied".localized : "Copy".localized) {
                        copyOutputToPasteboard(output, closeAfter: false)
                    }
                    BeautifulButton(
                        title: currentTask.insertBehavior == .append ? "Append".localized : "Accept".localized
                    ) {
                        accept()
                    }
                    .contextMenu {
                        Button {
                            accept(forceAppend: false)
                        } label: {
                            Label("Replace".localized, systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            accept(forceAppend: true)
                        } label: {
                            Label("Append".localized, systemImage: "text.append")
                        }
                    }
                }
                .frame(height: 38)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    @ViewBuilder
    private var readOnlyActionBar: some View {
        let primary = cfg.settings.readOnlyPrimaryAction
        HStack(spacing: 6) {
            BeautifulButton(title: "Discard".localized) { discard() }
            BeautifulButton(title: "Again".localized) { executeCurrentTask() }

            if primary == "share" {
                BeautifulButton(title: copiedToast ? "Copied".localized : "Copy".localized) {
                    copyOutputToPasteboard(output, closeAfter: false)
                }
                BeautifulButton(title: "Share") {
                    presentShareSheet(text: output)
                }
                .contextMenu { readOnlyContextMenu }
            } else {
                if cfg.settings.readOnlyShowShareButton {
                    BeautifulButton(title: "Share") {
                        presentShareSheet(text: output)
                    }
                }
                if primary == "copy" {
                    BeautifulButton(title: copiedToast ? "Copied".localized : "Copy".localized) {
                        copyOutputToPasteboard(output, closeAfter: false)
                    }
                    .contextMenu { readOnlyContextMenu }
                } else {
                    BeautifulButton(title: copiedToast ? "Copied".localized : "Copy & Close") {
                        copyOutputToPasteboard(output, closeAfter: true)
                    }
                    .contextMenu { readOnlyContextMenu }
                }
            }
        }
    }

    @ViewBuilder
    private var readOnlyContextMenu: some View {
        Button {
            copyOutputToPasteboard(output, closeAfter: false)
        } label: {
            Label("Copy Only", systemImage: "doc.on.doc")
        }
        Button {
            copyOutputToPasteboard(output, closeAfter: true)
        } label: {
            Label("Copy & Close", systemImage: "checkmark.circle")
        }
        Button {
            let qa = "Original:\n\(textProxy.selectedText)\n\nResult:\n\(output)"
            copyOutputToPasteboard(qa, closeAfter: false)
        } label: {
            Label("Copy Original + Result", systemImage: "doc.on.clipboard")
        }
        Button {
            presentShareSheet(text: output)
        } label: {
            Label("Share...", systemImage: "square.and.arrow.up")
        }
    }

    private func toggleSpeakOutput() {
        if isSpeakingOutput {
            OutputSpeechHelper.shared.stop()
            isSpeakingOutput = false
        } else {
            isSpeakingOutput = true
            OutputSpeechHelper.shared.speak(output) {
                isSpeakingOutput = false
            }
        }
    }

    private func navigateHistory(delta: Int) {
        if isEditingOutput, outputHistory.indices.contains(historyIndex) {
            outputHistory[historyIndex] = output
        }
        isEditingOutput = false
        let next = historyIndex + delta
        guard outputHistory.indices.contains(next) else { return }
        historyIndex = next
        output = outputHistory[next]
    }

    private func runFollowUp(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !output.isEmpty else { return }
        if isEditingOutput, outputHistory.indices.contains(historyIndex) {
            outputHistory[historyIndex] = output
        }
        followUpPromptInput = ""
        isEditingOutput = false
        currentTask = .followUp(
            originalText: textProxy.selectedText,
            currentOutput: output,
            instruction: trimmed
        )
        executeCurrentTask()
    }
}

private struct EditableOutputTextView: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.textColor = .white
        tv.tintColor = .white
        tv.font = .preferredFont(forTextStyle: .footnote)
        tv.isEditable = true
        tv.isScrollEnabled = true
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.text = text
        return tv
    }

    func updateUIView(_ uiView: UITextView, context _: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}

// MARK: - Word-Level Inline Diff View

private struct WordLevelDiffView: View {
    let original: String
    let updated: String

    var body: some View {
        let diff = WordDiffEngine.build(original: original, updated: updated)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("CHANGES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                if diff.addedWords > 0 {
                    Text("+\(diff.addedWords)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.56, green: 0.96, blue: 0.72))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.24))
                        .cornerRadius(4)
                }
                if diff.removedWords > 0 {
                    Text("-\(diff.removedWords)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.62, blue: 0.62))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.24))
                        .cornerRadius(4)
                }
                if diff.addedWords == 0, diff.removedWords == 0 {
                    Text("No changes")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
            }

            Text(diff.attributed)
                .multilineTextAlignment(.leading)
                .font(.system(.footnote))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private enum WordDiffEngine {
    enum OpKind {
        case equal
        case remove
        case add
    }

    struct Result {
        let attributed: AttributedString
        let addedWords: Int
        let removedWords: Int
    }

    static func build(original: String, updated: String) -> Result {
        let oldTokens = tokenize(original)
        let newTokens = tokenize(updated)

        var prefix = 0
        while prefix < oldTokens.count, prefix < newTokens.count, oldTokens[prefix] == newTokens[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < (oldTokens.count - prefix),
              suffix < (newTokens.count - prefix),
              oldTokens[oldTokens.count - 1 - suffix] == newTokens[newTokens.count - 1 - suffix]
        {
            suffix += 1
        }

        let midOld = Array(oldTokens[prefix ..< (oldTokens.count - suffix)])
        let midNew = Array(newTokens[prefix ..< (newTokens.count - suffix)])

        var ops: [(OpKind, String)] = []
        if prefix > 0 {
            ops.append((.equal, oldTokens[0 ..< prefix].joined()))
        }

        if midOld.isEmpty && midNew.isEmpty {
            // Identical
        } else if midOld.count * midNew.count > 160_000 {
            if !midOld.isEmpty {
                ops.append((.remove, midOld.joined()))
            }
            if !midNew.isEmpty {
                ops.append((.add, midNew.joined()))
            }
        } else {
            let n = midOld.count
            let m = midNew.count
            var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
            if n > 0, m > 0 {
                for i in stride(from: n - 1, through: 0, by: -1) {
                    for j in stride(from: m - 1, through: 0, by: -1) {
                        if midOld[i] == midNew[j] {
                            dp[i][j] = dp[i + 1][j + 1] + 1
                        } else {
                            dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                        }
                    }
                }
            }

            var i = 0
            var j = 0
            while i < n && j < m {
                if midOld[i] == midNew[j] {
                    appendMerged(&ops, kind: .equal, text: midOld[i])
                    i += 1
                    j += 1
                } else if dp[i + 1][j] >= dp[i][j + 1] {
                    appendMerged(&ops, kind: .remove, text: midOld[i])
                    i += 1
                } else {
                    appendMerged(&ops, kind: .add, text: midNew[j])
                    j += 1
                }
            }
            while i < n {
                appendMerged(&ops, kind: .remove, text: midOld[i])
                i += 1
            }
            while j < m {
                appendMerged(&ops, kind: .add, text: midNew[j])
                j += 1
            }
        }

        if suffix > 0 {
            appendMerged(&ops, kind: .equal, text: oldTokens[(oldTokens.count - suffix) ..< oldTokens.count].joined())
        }

        var attributed = AttributedString()
        var addedCount = 0
        var removedCount = 0

        for (kind, text) in ops {
            guard !text.isEmpty else { continue }
            var piece = AttributedString(text)
            switch kind {
            case .equal:
                piece.foregroundColor = Color.white.opacity(0.92)
            case .remove:
                let wordCount = countNonWhitespaceTokens(text)
                removedCount += wordCount
                piece.foregroundColor = Color(red: 1.0, green: 0.72, blue: 0.72)
                piece.backgroundColor = Color.red.opacity(0.30)
                piece.strikethroughStyle = .single
            case .add:
                let wordCount = countNonWhitespaceTokens(text)
                addedCount += wordCount
                piece.foregroundColor = Color(red: 0.70, green: 1.0, blue: 0.80)
                piece.backgroundColor = Color.green.opacity(0.30)
            }
            attributed.append(piece)
        }

        return Result(attributed: attributed, addedWords: addedCount, removedWords: removedCount)
    }

    private static func appendMerged(_ ops: inout [(OpKind, String)], kind: OpKind, text: String) {
        if let last = ops.last, last.0 == kind {
            ops[ops.count - 1].1 += text
        } else {
            ops.append((kind, text))
        }
    }

    private static func countNonWhitespaceTokens(_ text: String) -> Int {
        tokenize(text).filter { token in
            !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsWord = false
        var currentIsSpace = false

        for ch in text {
            let isSpace = ch.isWhitespace
            let isWord = !isSpace && (ch.isLetter || ch.isNumber || ch == "_" || ch == "'" || ch == "’")
            if current.isEmpty {
                current.append(ch)
                currentIsWord = isWord
                currentIsSpace = isSpace
            } else if isSpace && currentIsSpace {
                current.append(ch)
            } else if isWord && currentIsWord {
                current.append(ch)
            } else {
                tokens.append(current)
                current = String(ch)
                currentIsWord = isWord
                currentIsSpace = isSpace
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}

// MARK: - Output Text-to-Speech Helper

final class OutputSpeechHelper: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = OutputSpeechHelper()
    private let synthesizer = AVSpeechSynthesizer()
    private var onFinish: (() -> Void)?

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, onFinish: @escaping () -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onFinish()
            return
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        self.onFinish = onFinish
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        onFinish = nil
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.onFinish?()
            self?.onFinish = nil
        }
    }

    func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.onFinish?()
            self?.onFinish = nil
        }
    }
}

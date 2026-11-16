//
//  WritingToolsView+Output.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

import Combine
import Foundation
import SwiftUI
import UIKit

private let quickRefineChips: [(title: String, instruction: String)] = [
    ("Shorter", "Make this shorter and more concise."),
    ("Natural", "Make this sound more natural and fluent."),
    ("Formal", "Make this more formal and professional."),
    ("Fix Grammar", "Fix only spelling, grammar, and punctuation."),
    ("-> VI", "Translate this into natural Vietnamese."),
    ("-> EN", "Translate this into natural English."),
]

extension WritingToolsView {
    var outputPanel: some View {
        VStack(spacing: 8) {
            // Top mini-toolbar: version history, Original compare, Manual Edit
            if !output.isEmpty || outputHistory.count > 1 {
                HStack(spacing: 8) {
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

                    Spacer()

                    Button {
                        showOriginalDiff.toggle()
                        if showOriginalDiff { isEditingOutput = false }
                    } label: {
                        Label("Original".localized, systemImage: showOriginalDiff ? "eye.fill" : "eye")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(showOriginalDiff ? Color.white.opacity(0.28) : Color.white.opacity(0.12))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button {
                        isEditingOutput.toggle()
                        if isEditingOutput { showOriginalDiff = false }
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

                        if showOriginalDiff {
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

                        Text(output)
                            .multilineTextAlignment(.leading)
                            .font(.system(.footnote))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider().hidden()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            // Inline refine chips + follow-up prompt input (when idle with output)
            if !isRunning, !output.isEmpty {
                VStack(spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(quickRefineChips, id: \.title) { chip in
                                Button {
                                    runFollowUp(chip.instruction)
                                } label: {
                                    Text(chip.title)
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.13))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
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
                            TextField("Refine result or hold Mic...", text: $followUpPromptInput)
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
            } else {
                HStack(spacing: 6) {
                    BeautifulButton(title: "Discard".localized) { discard() }
                    BeautifulButton(title: "Again".localized) { executeCurrentTask() }
                    BeautifulButton(title: copiedToast ? "Copied".localized : "Copy".localized) {
                        UIPasteboard.general.string = output
                        copiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedToast = false
                        }
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

    private func navigateHistory(delta: Int) {
        let next = historyIndex + delta
        guard outputHistory.indices.contains(next) else { return }
        historyIndex = next
        output = outputHistory[next]
    }

    private func runFollowUp(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !output.isEmpty else { return }
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

//
//  WritingToolsView+Voice.swift
//  WritingTools
//

import Foundation
import SwiftUI
import UIKit

enum WritingVoiceLanguageCatalog {
    static let sourceOptions: [(code: String, label: String, short: String)] = [
        ("auto", "Auto Detect", "Auto"),
        ("vi", "Vietnamese", "VI"),
        ("en", "English", "EN"),
        ("zh", "Chinese", "ZH"),
        ("ja", "Japanese", "JA"),
        ("ko", "Korean", "KO"),
        ("fr", "French", "FR"),
        ("de", "German", "DE"),
        ("es", "Spanish", "ES"),
        ("th", "Thai", "TH"),
    ]

    static let targetOptions: [(code: String, label: String, short: String)] = [
        ("vi", "Vietnamese", "VI"),
        ("en", "English", "EN"),
        ("zh", "Chinese", "ZH"),
        ("ja", "Japanese", "JA"),
        ("ko", "Korean", "KO"),
        ("fr", "French", "FR"),
        ("de", "German", "DE"),
        ("es", "Spanish", "ES"),
        ("th", "Thai", "TH"),
    ]

    static func shortLabel(for code: String) -> String {
        let low = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let hit = sourceOptions.first(where: { $0.code == low }) {
            return hit.short
        }
        return low.isEmpty ? "Auto" : low.uppercased()
    }
}

extension WritingToolsView {
    var voiceModeAndLanguageStrip: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                voiceModeChip(id: "prompt", title: "Prompt", icon: "text.bubble")
                voiceModeChip(id: "dictate", title: "Dictate", icon: "waveform")
                voiceModeChip(id: "translate", title: "Translate", icon: "globe")
            }
            .padding(2)
            .background(Color.white.opacity(0.10))
            .cornerRadius(8)

            Spacer(minLength: 2)

            if voiceMode == "dictate" || voiceMode == "translate" {
                Menu {
                    ForEach(WritingVoiceLanguageCatalog.sourceOptions, id: \.code) { lang in
                        Button {
                            voiceSourceLang = lang.code
                        } label: {
                            if voiceSourceLang == lang.code {
                                Label(lang.label, systemImage: "checkmark")
                            } else {
                                Text(lang.label)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(WritingVoiceLanguageCatalog.shortLabel(for: voiceSourceLang))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.14))
                    .cornerRadius(6)
                    .foregroundColor(.white)
                }

                if voiceMode == "translate" {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))

                    Menu {
                        ForEach(WritingVoiceLanguageCatalog.targetOptions, id: \.code) { lang in
                            Button {
                                voiceTargetLang = lang.code
                            } label: {
                                if voiceTargetLang == lang.code {
                                    Label(lang.label, systemImage: "checkmark")
                                } else {
                                    Text(lang.label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(WritingVoiceLanguageCatalog.shortLabel(for: voiceTargetLang))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.22))
                        .cornerRadius(6)
                        .foregroundColor(.white)
                    }
                }
            }
        }
    }

    private func voiceModeChip(id: String, title: String, icon: String) -> some View {
        let active = (voiceMode == id)
        return Button {
            voiceMode = id
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: active ? .semibold : .medium))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(active ? Color.white.opacity(0.24) : Color.clear)
            .foregroundColor(active ? .white : .white.opacity(0.72))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    var liveRecordingStrip: some View {
        HStack(spacing: 7) {
            if isProcessingVoice {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
                Text(voiceMode == "translate" ? "Transcribing & translating..." : "Transcribing...")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
            } else {
                Circle()
                    .fill(voiceSlideWillCancel ? Color.orange : Color.red)
                    .frame(width: 8, height: 8)

                Text(formatDuration(voiceDuration))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundColor(.white)

                // Live waveform bars
                HStack(spacing: 2) {
                    ForEach(0 ..< voiceLevelHistory.count, id: \.self) { idx in
                        Capsule()
                            .fill(voiceSlideWillCancel ? Color.orange.opacity(0.85) : Color.white.opacity(0.85))
                            .frame(width: 2.5, height: max(4, voiceLevelHistory[idx] * 20))
                    }
                }
                .frame(height: 22)

                Spacer(minLength: 2)

                if voiceHoldActive {
                    Text(voiceSlideWillCancel ? "Release to cancel" : "← Slide cancel")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(voiceSlideWillCancel ? .orange : .white.opacity(0.75))
                        .lineLimit(1)
                } else {
                    Button {
                        cancelVoiceCapture()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(voiceSlideWillCancel ? Color.red.opacity(0.26) : Color.white.opacity(0.16))
        )
    }

    func makeMicButton(isFollowUp: Bool) -> some View {
        VoiceMicTouchButton(
            isRecording: isRecordingVoice && (voiceTargetIsFollowUp == isFollowUp),
            isProcessing: isProcessingVoice,
            onTouchDown: {
                guard !isProcessingVoice else { return }
                if isRecordingVoice {
                    // Already in tap-to-talk locked mode -> tap stops & processes
                    stopAndProcessVoice()
                } else {
                    beginVoiceCapture(isFollowUp: isFollowUp)
                }
            },
            onHoldActivated: {
                if isRecordingVoice {
                    voiceHoldActive = true
                }
            },
            onSlideCancelChanged: { willCancel in
                if isRecordingVoice, voiceHoldActive {
                    voiceSlideWillCancel = willCancel
                }
            },
            onHoldReleased: { shouldCancel in
                guard isRecordingVoice else { return }
                if shouldCancel {
                    cancelVoiceCapture()
                } else {
                    stopAndProcessVoice()
                }
            }
        )
        .frame(width: 30, height: 30)
    }

    func beginVoiceCapture(isFollowUp: Bool) {
        voiceBannerMessage = ""
        voiceTargetIsFollowUp = isFollowUp
        voiceHoldActive = false
        voiceSlideWillCancel = false
        voiceDuration = 0
        voiceLevel = 0
        voiceLevelHistory = Array(repeating: 0.12, count: 18)

        cfg.startVoiceRecording { ok, err in
            if !ok {
                isRecordingVoice = false
                voiceBannerMessage = err ?? "Could not start microphone."
                return
            }
            isRecordingVoice = true
            startVoicePolling()
        }
    }

    func cancelVoiceCapture() {
        stopVoicePolling()
        isRecordingVoice = false
        voiceHoldActive = false
        voiceSlideWillCancel = false
        cfg.cancelVoiceRecording()
    }

    func stopAndProcessVoice() {
        guard isRecordingVoice else { return }
        stopVoicePolling()
        isRecordingVoice = false
        voiceHoldActive = false
        voiceSlideWillCancel = false
        isProcessingVoice = true

        let effectiveMode = voiceTargetIsFollowUp ? "prompt" : voiceMode
        cfg.stopVoiceRecording(
            mode: effectiveMode,
            sourceLanguage: voiceSourceLang,
            targetLanguage: voiceTargetLang
        ) { ok, transcript, finalText, _, warning, errMsg in
            isProcessingVoice = false
            if !ok {
                voiceBannerMessage = errMsg ?? "Voice transcription failed."
                return
            }
            if let warning, !warning.isEmpty {
                voiceBannerMessage = warning
            } else {
                voiceBannerMessage = ""
            }
            handleVoiceResult(
                mode: effectiveMode,
                isFollowUp: voiceTargetIsFollowUp,
                transcript: transcript,
                finalText: finalText
            )
        }
    }

    private func handleVoiceResult(
        mode: String,
        isFollowUp: Bool,
        transcript: String,
        finalText: String
    ) {
        let trimmedFinal = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFinal.isEmpty else {
            voiceBannerMessage = "No speech recognized."
            return
        }

        if isFollowUp {
            if cfg.settings.stt.autoSendVoicePrompt {
                followUpPromptInput = ""
                isEditingOutput = false
                currentTask = .followUp(
                    originalText: textProxy.selectedText,
                    currentOutput: output,
                    instruction: trimmedFinal
                )
                executeCurrentTask()
            } else {
                followUpPromptInput = trimmedFinal
            }
            return
        }

        switch mode {
        case "dictate", "translate":
            voiceLastTranscript = (mode == "translate" && transcript != trimmedFinal) ? transcript : ""
            currentTask = .customPrompt(mode == "translate" ? "Voice Translate" : "Voice Dictate")
            output = trimmedFinal
            outputHistory.append(trimmedFinal)
            historyIndex = outputHistory.count - 1
            isEditingOutput = false
            diffDisplayMode = .none
            persistSessionSnapshot()

        default: // "prompt"
            if cfg.settings.stt.autoSendVoicePrompt {
                runCustomPrompt(trimmedFinal)
            } else {
                customPromptInput = trimmedFinal
            }
        }
    }

    private func stopVoicePolling() {
        voicePollTimer?.invalidate()
        voicePollTimer = nil
    }

    private func startVoicePolling() {
        stopVoicePolling()
        voicePollTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            guard isRecordingVoice else {
                voicePollTimer?.invalidate()
                voicePollTimer = nil
                return
            }
            cfg.fetchSTTStatus { recording, dur, lvl, maxDur in
                guard isRecordingVoice else { return }
                voiceDuration = dur
                voiceLevel = lvl
                var next = voiceLevelHistory
                if !next.isEmpty {
                    next.removeFirst()
                    next.append(CGFloat(max(0.08, min(1.0, lvl))))
                    voiceLevelHistory = next
                }
                if !recording && dur >= max(1.0, maxDur - 0.5) {
                    stopAndProcessVoice()
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct VoiceMicTouchButton: UIViewRepresentable {
    let isRecording: Bool
    let isProcessing: Bool
    let onTouchDown: () -> Void
    let onHoldActivated: () -> Void
    let onSlideCancelChanged: (Bool) -> Void
    let onHoldReleased: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MicControlView {
        let view = MicControlView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MicControlView, context: Context) {
        context.coordinator.parent = self
        uiView.updateAppearance(isRecording: isRecording, isProcessing: isProcessing)
    }

    final class Coordinator {
        var parent: VoiceMicTouchButton
        init(parent: VoiceMicTouchButton) { self.parent = parent }
    }

    final class MicControlView: UIView {
        weak var coordinator: Coordinator?
        private let bgView = UIView()
        private let iconView = UIImageView()

        private var holdTimer: Timer?
        private var startedHoldMode = false
        private var startedInRecordingState = false
        private var startPoint: CGPoint = .zero
        private var slideWillCancel = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = false
            isExclusiveTouch = true

            bgView.isUserInteractionEnabled = false
            bgView.layer.cornerRadius = 15
            addSubview(bgView)

            iconView.isUserInteractionEnabled = false
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = .white
            addSubview(iconView)

            updateAppearance(isRecording: false, isProcessing: false)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            bgView.frame = bounds
            bgView.layer.cornerRadius = min(bounds.width, bounds.height) * 0.5
            iconView.frame = bounds.insetBy(dx: 7, dy: 7)
        }

        func updateAppearance(isRecording: Bool, isProcessing: Bool) {
            if isProcessing {
                bgView.backgroundColor = UIColor.white.withAlphaComponent(0.14)
                iconView.image = UIImage(systemName: "ellipsis")
                iconView.tintColor = UIColor.white.withAlphaComponent(0.6)
            } else if isRecording {
                bgView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.92)
                iconView.image = UIImage(systemName: "stop.fill")
                iconView.tintColor = .white
            } else {
                bgView.backgroundColor = UIColor.white.withAlphaComponent(0.18)
                iconView.image = UIImage(systemName: "mic.fill")
                iconView.tintColor = .white
            }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard let coord = coordinator, !coord.parent.isProcessing else { return }
            startedInRecordingState = coord.parent.isRecording
            startedHoldMode = false
            slideWillCancel = false
            startPoint = touches.first?.location(in: self) ?? .zero

            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIView.animate(withDuration: 0.1) {
                self.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
            }

            coord.parent.onTouchDown()

            if !startedInRecordingState {
                holdTimer?.invalidate()
                holdTimer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    self.startedHoldMode = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    self.coordinator?.parent.onHoldActivated()
                }
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
            guard startedHoldMode, let pt = touches.first?.location(in: self) else { return }
            let dx = pt.x - startPoint.x
            let shouldCancel = dx <= -44
            if shouldCancel != slideWillCancel {
                slideWillCancel = shouldCancel
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                coordinator?.parent.onSlideCancelChanged(shouldCancel)
            }
        }

        override func touchesEnded(_: Set<UITouch>, with _: UIEvent?) {
            finishTouch(cancelled: false)
        }

        override func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
            finishTouch(cancelled: true)
        }

        private func finishTouch(cancelled: Bool) {
            holdTimer?.invalidate()
            holdTimer = nil
            UIView.animate(withDuration: 0.14) {
                self.transform = .identity
            }
            if startedHoldMode {
                let shouldCancel = cancelled || slideWillCancel
                coordinator?.parent.onHoldReleased(shouldCancel)
            }
            startedHoldMode = false
            slideWillCancel = false
        }
    }
}

//
//  WritingToolsView+Execute.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

import Combine
import Foundation
import OpenAI
import UIKit
import WritingToolsLocalizable

extension WritingToolsView {
    func executeCurrentTask(delayedForRetry: Bool = false) {
        let shouldDelayForAnimation = !output.isEmpty
        let requestToken = UUID()
        activeRequestToken = requestToken

        cfg.openAI.cancelAllStreams()
        isEditingOutput = false
        isRunning = true
        output = ""
        error = nil

        let text = context.textProxy.selectedText
        let settings = cfg.settings
        let taskToRun = currentTask
        let built = PromptComposer.buildMessages(for: taskToRun, selectedText: text, settings: settings)
        let query = ChatQuery(
            messages: built.messages,
            model: cfg.mid,
            temperature: built.sampling.temperature,
            topP: built.sampling.topP
        )

        let useStreaming = settings.streamingEnabled && (cfg.activeEndpoint?.useStreaming ?? true)
        let stripThink = settings.stripThinkingTags

        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + (shouldDelayForAnimation ? 0.2 : 0) + (delayedForRetry ? 2 : 0)
        ) {
            if useStreaming {
                runStreamingQuery(query: query, stripThink: stripThink, requestToken: requestToken)
            } else {
                runNonStreamingQuery(query: query, stripThink: stripThink, requestToken: requestToken)
            }
        }
    }

    private func runStreamingQuery(query: ChatQuery, stripThink: Bool, requestToken: UUID) {
        var completed = false
        var rawAccumulated = ""
        var firstError: Error?

        let outputSender = CurrentValueSubject<String, Never>("")
        var cancellable: (any Cancellable)? = outputSender
            .throttle(for: .seconds(0.05), scheduler: DispatchQueue.global(qos: .userInteractive), latest: true)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { chunk in
                guard !completed, activeRequestToken == requestToken else { return }
                let formatted = stripThink ? PromptComposer.stripThinkingTags(from: chunk) : chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                output = formatted
            }

        cfg.openAI.chatsStream(query: query) { partialResult in
            switch partialResult {
            case let .success(result):
                let newToken = result.choices.compactMap(\.delta.content).joined()
                if !newToken.isEmpty {
                    rawAccumulated += newToken
                    outputSender.send(rawAccumulated)
                }
            case let .failure(err):
                if firstError == nil {
                    firstError = err
                }
            }
        } completion: { completionError in
            completed = true
            cancellable?.cancel()
            cancellable = nil

            let rawTrimmed = rawAccumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            var finalFormatted = stripThink
                ? PromptComposer.stripThinkingTags(from: rawAccumulated)
                : rawTrimmed
            if finalFormatted.isEmpty, !rawTrimmed.isEmpty {
                finalFormatted = rawTrimmed
                    .replacingOccurrences(of: "<think>", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let finalError = firstError ?? completionError

            // If streaming yielded zero text (e.g. provider returned plain JSON instead of SSE), try non-streaming once
            if finalFormatted.isEmpty,
               finalError is DecodingError || (finalError as? OpenAIError) == .nonStreamingPayload
            {
                runNonStreamingQuery(query: query, stripThink: stripThink, requestToken: requestToken)
                return
            }

            DispatchQueue.main.async {
                guard self.activeRequestToken == requestToken else { return }
                if !finalFormatted.isEmpty {
                    self.output = finalFormatted
                    self.appendHistory(finalFormatted)
                    self.isRunning = false
                    self.error = nil
                } else {
                    self.onEmptyCompletion(upstreamError: finalError)
                }
            }
        }
    }

    private func runNonStreamingQuery(query: ChatQuery, stripThink: Bool, requestToken: UUID) {
        cfg.openAI.chats(query: query) { result in
            DispatchQueue.main.async {
                guard self.activeRequestToken == requestToken else { return }
                switch result {
                case let .success(chatResult):
                    let raw = chatResult.choices.compactMap { $0.message.content?.string }.joined()
                    let rawTrimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    var finalFormatted = stripThink
                        ? PromptComposer.stripThinkingTags(from: raw)
                        : rawTrimmed
                    if finalFormatted.isEmpty, !rawTrimmed.isEmpty {
                        finalFormatted = rawTrimmed
                            .replacingOccurrences(of: "<think>", with: "", options: .caseInsensitive)
                            .replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if !finalFormatted.isEmpty {
                        self.output = finalFormatted
                        self.appendHistory(finalFormatted)
                        self.isRunning = false
                        self.error = nil
                    } else {
                        self.onEmptyCompletion(upstreamError: nil)
                    }
                case let .failure(err):
                    self.onEmptyCompletion(upstreamError: err)
                }
            }
        }
    }

    private func appendHistory(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if outputHistory.last != trimmed {
            outputHistory.append(trimmed)
        }
        historyIndex = max(0, outputHistory.count - 1)
    }

    func stopStreaming() {
        activeRequestToken = UUID()
        cfg.openAI.cancelAllStreams()
        isRunning = false
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            output = trimmed
            appendHistory(trimmed)
        }
    }

    static let spawnURL = URL(string: "writenow://spawn")

    func onEmptyCompletion(upstreamError: Error?) {
        assert(Thread.isMainThread)

        DispatchQueue.global(qos: .userInteractive).async {
            let request = Configurator.shared.gateErrorCheckRequest
            var daemonErrorMessage: String?
            var reachable = false
            let sem = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: request) { data, _, err in
                defer { sem.signal() }
                guard err == nil, let data else { return }
                reachable = true
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    let msg = json["error"] ?? json["last_error"] ?? ""
                    if !msg.isEmpty {
                        daemonErrorMessage = msg
                    }
                }
            }.resume()
            _ = sem.wait(timeout: .now() + 2.5)

            if !reachable {
                let nsErr = NSError(
                    domain: WritingToolsLocalizable.shared.localizedMenuItemTitle(),
                    code: kErrorCodeRetry,
                    userInfo: [
                        NSLocalizedDescriptionKey: WritingToolsLocalizable.shared.localizedString(
                            forKey: "Unable to establish a secure connection to daemon"
                        ),
                    ]
                )
                completeWithError(nsErr)
                return
            }

            let message: String
            if let daemonErrorMessage, !daemonErrorMessage.isEmpty {
                message = daemonErrorMessage
            } else if let apiErr = upstreamError as? APIErrorResponse {
                message = apiErr.error.message
            } else if let upstreamError {
                message = upstreamError.localizedDescription
            } else {
                message = "Empty response from model."
            }

            let nsErr = NSError(
                domain: WritingToolsLocalizable.shared.localizedMenuItemTitle(),
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
            completeWithError(nsErr)
        }
    }

    func completeNormally() {
        DispatchQueue.main.async {
            isRunning = false
            error = nil
        }
    }

    func completeWithError(_ error: NSError) {
        var shouldOpenAIGate = false
        let spawnURL = Self.spawnURL
        if error.code == kErrorCodeRetry, let spawnURL, UIApplication.shared.canOpenURL(spawnURL) {
            shouldOpenAIGate = true
        }
        DispatchQueue.main.async {
            if shouldOpenAIGate, !isRetrying, let spawnURL {
                UIApplication.shared.open(spawnURL)
                self.setNeedsRetryWhenActive()
            }
            isRunning = false
            self.error = error
        }
    }

    func discard() {
        activeRequestToken = UUID()
        cfg.openAI.cancelAllStreams()
        isRunning = false
        isEditingOutput = false
        showOriginalDiff = false
        output = ""
    }

    func accept(forceAppend: Bool? = nil) {
        let shouldAppend = forceAppend ?? (currentTask.insertBehavior == .append)
        let finalText = output
        let captured = TextTransitionAnimator.captureBeforeReplace(context: context)
        let animatedDisplayText: String
        if shouldAppend {
            let existing = context.textProxy.selectedText
            if existing.isEmpty {
                animatedDisplayText = finalText
            } else if existing.hasSuffix("\n") {
                animatedDisplayText = "\(existing)\(finalText)"
            } else {
                animatedDisplayText = "\(existing)\n\n\(finalText)"
            }
        } else {
            animatedDisplayText = finalText
        }

        dismiss()
        if shouldAppend {
            context.textProxy.appendText(with: finalText)
        } else {
            context.textProxy.replaceText(with: finalText)
        }
        if let captured {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                TextTransitionAnimator.play(capture: captured, newText: animatedDisplayText)
            }
        }
    }
}

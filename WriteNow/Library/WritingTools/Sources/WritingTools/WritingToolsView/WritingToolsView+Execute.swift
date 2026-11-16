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

        isRunning = true
        output = ""

    let text = context.textProxy.selectedText
    // Adaptive sampling based on input length
    let sampling = taskPrompt.sampling(for: text.count)
        let query = ChatQuery(
            messages: [.system(.init(content: taskPrompt.prompt))]
                + taskPrompt.chatExamplesAfterSystemMessage
                + [.user(.init(content: .init(string:
                    """
                    \(Prompt.userContentHeader)

                    \(text)
                    """
                )))],
            model: cfg.mid,
            temperature: sampling.temperature,
            topP: sampling.topP
        )

        var completed = false
        let outputSender = CurrentValueSubject<String, Never>("")
        var cancellable: (any Cancellable)? = outputSender
            .throttle(for: .seconds(0.05), scheduler: DispatchQueue.global(qos: .userInteractive), latest: true)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink {
                guard !completed else {
                    return
                }
                output = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + (shouldDelayForAnimation ? 0.25 : 0) + (delayedForRetry ? 2 : 0)) {
            cfg.openAI.chatsStream(query: query) { partialResult in
                switch partialResult {
                case let .success(result):
                    let newToken = result.choices.compactMap(\.delta.content).joined()
                    let value = outputSender.value + newToken
                    outputSender.send(value)
                default: break
                }
            } completion: { _ in
                completed = true
                outputSender.send(outputSender.value)
                cancellable?.cancel()
                cancellable = nil

                let finalValue = outputSender.value.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    output = finalValue
                }

                DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.1) {
                    onCompletion()
                }
            }
        }
    }

    static let spawnURL = URL(string: "writenow://spawn")

    func onCompletion() {
        assert(!Thread.isMainThread)

        if !output.isEmpty {
            completeNormally()
            return
        }

        let request = Configurator.shared.gateErrorCheckRequest
        var checkError: NSError?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { sem.signal() }
            guard let data else { return }
            guard let json = try? JSONSerialization.jsonObject(
                with: data, options: []
            ) as? [String: String] else { return }
            guard let lastError = json["last_error"] else { return }
            checkError = NSError(
                domain: WritingToolsLocalizable.shared.localizedMenuItemTitle(),
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: lastError,
                ]
            )
        }.resume()
        _ = sem.wait(timeout: .now() + 3)

        guard let checkError else {
            completeWithError(NSError(
                domain: WritingToolsLocalizable.shared.localizedMenuItemTitle(),
                code: kErrorCodeRetry,
                userInfo: [
                    NSLocalizedDescriptionKey: WritingToolsLocalizable.shared.localizedString(
                        forKey: "Unable to establish a secure connection to daemon"
                    ),
                ]
            ))
            return
        }

        completeWithError(checkError)
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
        isRunning = false
        output = ""
    }

    func accept() {
        dismiss()
        context.textProxy.replaceText(with: output)
    }

    private func location(forTextRagne textRange: UITextRange, inTextView textView: UITextView) -> Int {
        let beginning = textView.beginningOfDocument
        let start = textRange.start
        return textView.offset(from: beginning, to: start)
    }

    private func length(forTextRange textRange: UITextRange, inTextView textView: UITextView) -> Int {
        let start = textRange.start
        let end = textRange.end
        return textView.offset(from: start, to: end)
    }

    private func stringRange(forTextRange textRange: UITextRange, inTextView textView: UITextView) -> NSRange {
        let location = location(forTextRagne: textRange, inTextView: textView)
        let length = length(forTextRange: textRange, inTextView: textView)
        return NSRange(location: location, length: length)
    }
}

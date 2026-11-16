//
//  StreamingSession.swift
//
//
//  Created by Sergii Kryvoblotskyi on 18/04/2023.
//

import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

protocol CancellableStream: AnyObject {
    func cancel()
}

final class StreamingSession<ResultType: Codable>: NSObject, Identifiable, URLSessionDelegate, URLSessionDataDelegate, CancellableStream {
    enum StreamingError: Error {
        case unknownContent
        case emptyContent
    }

    var onReceiveContent: ((StreamingSession, ResultType) -> Void)?
    var onProcessingError: ((StreamingSession, Error) -> Void)?
    var onComplete: ((StreamingSession, Error?) -> Void)?

    private let streamingCompletionMarker = "[DONE]"
    private let urlRequest: URLRequest
    private lazy var urlSession: URLSession = {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        return session
    }()

    private var dataTask: URLSessionDataTask?
    private var previousChunkBuffer = ""
    private var rawNonSSEBuffer = ""
    private var receivedAnySSEData = false
    private var isCancelledManually = false

    init(urlRequest: URLRequest) {
        self.urlRequest = urlRequest
    }

    func perform() {
        let task: URLSessionDataTask = urlSession.dataTask(with: urlRequest)
        dataTask = task
        task.resume()
    }

    func cancel() {
        isCancelledManually = true
        dataTask?.cancel()
        urlSession.invalidateAndCancel()
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        if !previousChunkBuffer.isEmpty {
            processSSEBuffer(flushRemaining: true)
        }
        if !receivedAnySSEData, !rawNonSSEBuffer.isEmpty {
            let trimmed = rawNonSSEBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = trimmed.data(using: .utf8) {
                let decoder = JSONDecoder()
                if let object = try? decoder.decode(ResultType.self, from: data) {
                    onReceiveContent?(self, object)
                } else if let apiError = try? decoder.decode(APIErrorResponse.self, from: data) {
                    onProcessingError?(self, apiError)
                }
            }
        }
        urlSession.finishTasksAndInvalidate()
        onComplete?(self, isCancelledManually ? nil : error)
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        guard let stringContent = String(data: data, encoding: .utf8) else {
            onProcessingError?(self, StreamingError.unknownContent)
            return
        }
        processJSON(from: stringContent)
    }
}

extension StreamingSession {
    private func processJSON(from stringContent: String) {
        if stringContent.isEmpty {
            return
        }
        let normalized = stringContent
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        previousChunkBuffer += normalized
        if !receivedAnySSEData {
            rawNonSSEBuffer += normalized
        }
        processSSEBuffer(flushRemaining: false)
    }

    private func processSSEBuffer(flushRemaining: Bool) {
        while let newlineRange = previousChunkBuffer.range(of: "\n") {
            let line = String(previousChunkBuffer[..<newlineRange.lowerBound])
            previousChunkBuffer.removeSubrange(..<newlineRange.upperBound)
            processSSELine(line)
        }
        if flushRemaining, !previousChunkBuffer.isEmpty {
            let remaining = previousChunkBuffer
            previousChunkBuffer = ""
            processSSELine(remaining)
        }
    }

    private func processSSELine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        // Ignore SSE comments (e.g. ": OPENROUTER PROCESSING") and control fields
        if line.hasPrefix(":") || line.hasPrefix("event:") || line.hasPrefix("id:") || line.hasPrefix("retry:") {
            return
        }

        let payload: String
        if line.hasPrefix("data:") {
            receivedAnySSEData = true
            rawNonSSEBuffer = ""
            payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return
        }

        guard !payload.isEmpty, payload != streamingCompletionMarker else {
            return
        }
        guard let jsonData = payload.data(using: .utf8) else {
            onProcessingError?(self, StreamingError.unknownContent)
            return
        }

        let decoder = JSONDecoder()
        do {
            let object = try decoder.decode(ResultType.self, from: jsonData)
            onReceiveContent?(self, object)
        } catch {
            if let decoded = try? decoder.decode(APIErrorResponse.self, from: jsonData) {
                onProcessingError?(self, decoded)
            } else {
                onProcessingError?(self, error)
            }
        }
    }
}

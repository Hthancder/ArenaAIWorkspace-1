//
//  AIGateProxySwitchHandler.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/15.
//

import Foundation
import NIO

class AIGateProxySwitchHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    let proxyHandler: AIGateProxyHandler
    var headerBuffer = Data()
    var isHeaderChecked = false
    var failedStatusCode: Int?
    var errorBodyBuffer = Data()
    var errorExpectedLength: Int?
    var errorIsChunked = false
    var errorFlushTask: Scheduled<Void>?
    private let maxErrorBodyBytes = 16 * 1024

    init(proxyHandler: AIGateProxyHandler) {
        self.proxyHandler = proxyHandler
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)

        if let failedCode = failedStatusCode {
            if errorBodyBuffer.count < maxErrorBodyBytes,
               let bytes = buffer.getBytes(at: buffer.readerIndex, length: min(buffer.readableBytes, maxErrorBodyBytes - errorBodyBuffer.count))
            {
                errorBodyBuffer.append(contentsOf: bytes)
            }
            checkFailedErrorCompletion(context: context, code: failedCode)
            return
        }

        if isHeaderChecked {
            proxyHandler.writeBack(buffer: buffer)
            return
        }

        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else {
            proxyHandler.context.terminateChannel(reason: .invalidResponse)
            context.close(mode: .all, promise: nil)
            return
        }
        headerBuffer.append(contentsOf: bytes)

        let delimiter = "\r\n\r\n".data(using: .utf8)!
        guard let range = headerBuffer.range(of: delimiter) else {
            if headerBuffer.count > 32 * 1024 {
                proxyHandler.context.terminateChannel(reason: .invalidResponse)
                context.close(mode: .all, promise: nil)
            }
            return
        }

        let headerData = headerBuffer.subdata(in: 0 ..< range.lowerBound)
        let trailingData = headerBuffer.subdata(in: range.upperBound ..< headerBuffer.count)
        headerBuffer = Data()

        guard let headerString = String(data: headerData, encoding: .utf8),
              let statusLine = headerString.components(separatedBy: "\r\n").first
        else {
            proxyHandler.context.terminateChannel(reason: .invalidResponse)
            context.close(mode: .all, promise: nil)
            return
        }

        let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, let code = Int(parts[1]) else {
            proxyHandler.context.terminateChannel(reason: .invalidResponse)
            context.close(mode: .all, promise: nil)
            return
        }

        isHeaderChecked = true

        if (200 ..< 300).contains(code) {
            var outBuf = context.channel.allocator.buffer(capacity: headerData.count + delimiter.count + trailingData.count)
            outBuf.writeBytes(headerData)
            outBuf.writeBytes(delimiter)
            outBuf.writeBytes(trailingData)
            proxyHandler.writeBack(buffer: outBuf)
            ServiceError.recordSuccess(
                endpointName: proxyHandler.upstream.endpointName,
                startNs: proxyHandler.requestStartNs
            )
        } else {
            failedStatusCode = code
            errorExpectedLength = parseContentLength(from: headerString)
            errorIsChunked = isChunkedEncoding(in: headerString)
            if !trailingData.isEmpty {
                errorBodyBuffer.append(trailingData.prefix(maxErrorBodyBytes))
            }
            errorFlushTask = context.eventLoop.scheduleTask(in: .seconds(2)) { [weak self] in
                guard let self, let pendingCode = self.failedStatusCode else { return }
                self.finishFailedResponse(context: context, code: pendingCode)
            }
            checkFailedErrorCompletion(context: context, code: code)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        errorFlushTask?.cancel()
        errorFlushTask = nil
        if proxyHandler.didTriggerFallback {
            return
        }
        if let failedCode = failedStatusCode {
            finishFailedResponse(context: context, code: failedCode)
            return
        }
        if !isHeaderChecked {
            proxyHandler.handleFailureBeforeOutput(reason: .invalidResponse)
            return
        }
        proxyHandler.context.close(mode: .all, promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error _: Error) {
        errorFlushTask?.cancel()
        errorFlushTask = nil
        if proxyHandler.didTriggerFallback {
            return
        }
        if let failedCode = failedStatusCode {
            finishFailedResponse(context: context, code: failedCode)
            return
        }
        proxyHandler.handleFailureBeforeOutput(reason: .endpointNotReachable)
        context.close(mode: .all, promise: nil)
    }

    private func checkFailedErrorCompletion(context: ChannelHandlerContext, code: Int) {
        if let expected = errorExpectedLength {
            if errorBodyBuffer.count >= expected || errorBodyBuffer.count >= maxErrorBodyBytes {
                finishFailedResponse(context: context, code: code)
            }
            return
        }
        if errorIsChunked {
            if decodeChunked(errorBodyBuffer) != nil || errorBodyBuffer.count >= maxErrorBodyBytes {
                finishFailedResponse(context: context, code: code)
            }
            return
        }
        if errorBodyBuffer.count >= maxErrorBodyBytes {
            finishFailedResponse(context: context, code: code)
        }
    }

    private func finishFailedResponse(context: ChannelHandlerContext, code: Int) {
        errorFlushTask?.cancel()
        errorFlushTask = nil
        failedStatusCode = nil

        let rawBody: Data
        if errorIsChunked, let decoded = decodeChunked(errorBodyBuffer) {
            rawBody = decoded
        } else if let expected = errorExpectedLength, expected >= 0, errorBodyBuffer.count >= expected {
            rawBody = Data(errorBodyBuffer.prefix(expected))
        } else {
            rawBody = errorBodyBuffer
        }

        let detail = extractErrorDetail(from: rawBody)
        let reason: ServiceError = .upstreamPassedError(code: code, detail: detail)
        if code == 429 || (500 ... 599).contains(code) {
            proxyHandler.handleFailureBeforeOutput(reason: reason)
        } else {
            proxyHandler.context.terminateChannel(reason: reason)
        }
        context.close(mode: .all, promise: nil)
    }

    private func parseContentLength(from headerString: String) -> Int? {
        for line in headerString.components(separatedBy: "\r\n").dropFirst() {
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces)
            if key.caseInsensitiveCompare("Content-Length") == .orderedSame {
                let val = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                return Int(val)
            }
        }
        return nil
    }

    private func isChunkedEncoding(in headerString: String) -> Bool {
        for line in headerString.components(separatedBy: "\r\n").dropFirst() {
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces)
            if key.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame {
                let val = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                if val.lowercased().contains("chunked") {
                    return true
                }
            }
        }
        return false
    }

    private func decodeChunked(_ data: Data) -> Data? {
        let crlf = Data("\r\n".utf8)
        var offset = 0
        var decoded = Data()
        while offset < data.count {
            guard let lineEnd = data.range(of: crlf, options: [], in: offset ..< data.count) else {
                return nil
            }
            let sizeLineData = data.subdata(in: offset ..< lineEnd.lowerBound)
            guard let sizeLine = String(data: sizeLineData, encoding: .utf8) else { return nil }
            let hexPart = sizeLine.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let chunkSize = Int(hexPart, radix: 16) else { return nil }
            offset = lineEnd.upperBound
            if chunkSize == 0 {
                return decoded
            }
            guard offset + chunkSize + 2 <= data.count else { return nil }
            decoded.append(data.subdata(in: offset ..< offset + chunkSize))
            offset += chunkSize + 2
        }
        return nil
    }

    private func extractErrorDetail(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorObj = obj["error"] as? [String: Any], let msg = errorObj["message"] as? String {
                return msg
            }
            if let msg = obj["message"] as? String {
                return msg
            }
            if let detail = obj["detail"] as? String {
                return detail
            }
            if let errorStr = obj["error"] as? String {
                return errorStr
            }
        }
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty
        {
            return String(text.prefix(280))
        }
        return nil
    }
}

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
            if errorBodyBuffer.count >= maxErrorBodyBytes {
                finishFailedResponse(context: context, code: failedCode)
            }
            return
        }

        if isHeaderChecked {
            proxyHandler.writeBack(buffer: buffer)
            return
        }

        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else {
            context.terminateChannel(reason: .invalidResponse)
            return
        }
        headerBuffer.append(contentsOf: bytes)

        let delimiter = "\r\n\r\n".data(using: .utf8)!
        guard let range = headerBuffer.range(of: delimiter) else {
            if headerBuffer.count > 32 * 1024 {
                context.terminateChannel(reason: .invalidResponse)
            }
            return
        }

        let headerData = headerBuffer.subdata(in: 0 ..< range.lowerBound)
        let trailingData = headerBuffer.subdata(in: range.upperBound ..< headerBuffer.count)
        headerBuffer = Data()

        guard let headerString = String(data: headerData, encoding: .utf8),
              let statusLine = headerString.components(separatedBy: "\r\n").first
        else {
            context.terminateChannel(reason: .invalidResponse)
            return
        }

        let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, let code = Int(parts[1]) else {
            context.terminateChannel(reason: .invalidResponse)
            return
        }

        isHeaderChecked = true

        if (200 ..< 300).contains(code) {
            var outBuf = context.channel.allocator.buffer(capacity: headerData.count + delimiter.count + trailingData.count)
            outBuf.writeBytes(headerData)
            outBuf.writeBytes(delimiter)
            outBuf.writeBytes(trailingData)
            proxyHandler.writeBack(buffer: outBuf)
            ServiceError.lastError = nil
        } else {
            failedStatusCode = code
            if !trailingData.isEmpty {
                errorBodyBuffer.append(trailingData.prefix(maxErrorBodyBytes))
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        if let failedCode = failedStatusCode {
            finishFailedResponse(context: context, code: failedCode)
            return
        }
        proxyHandler.context.close(mode: .all, promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error _: Error) {
        if let failedCode = failedStatusCode {
            finishFailedResponse(context: context, code: failedCode)
            return
        }
        proxyHandler.context.terminateChannel(reason: .endpointNotReachable)
    }

    private func finishFailedResponse(context: ChannelHandlerContext, code: Int) {
        failedStatusCode = nil
        let detail = extractErrorDetail(from: errorBodyBuffer)
        proxyHandler.context.terminateChannel(reason: .upstreamPassedError(code: code, detail: detail))
        context.close(mode: .all, promise: nil)
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

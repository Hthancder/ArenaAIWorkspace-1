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
    typealias InboundOut = ByteBuffer

    let downstream: ChannelHandlerContext

    var headerBuffer = Data()
    var headerCompleted = false
    var bodyBuffer = Data()
    var bodyBufferForWrite = Data()

    init(downstream: ChannelHandlerContext) {
        self.downstream = downstream
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var inputBuffer = unwrapInboundIn(data)
        guard let inputRead = inputBuffer.readBytes(length: inputBuffer.readableBytes) else { return }
        let inputData = Data(inputRead)

        switch headerCompleted {
        case false:
            assert(bodyBuffer.isEmpty)

            let parts = splitInputDataForHTTP(currentData: headerBuffer, incomingData: inputData)
            headerBuffer = parts.header
            bodyBuffer = parts.body
            headerCompleted = parts.headerCompleted

        case true:
            // into body status, header must be processed before
            bodyBuffer.append(inputData)
            writeToDownstream(context: context)
            return
        }

        guard headerCompleted else { return }

        guard let code = codeFromHeader() else {
            context.terminateChannel(reason: .upstreamUnrecognizedResponse)
            return
        }
        guard code == 200 else {
            context.terminateChannel(reason: .upstreamPassedError(code: code))
            return
        }
        writeToDownstream(context: context)
    }

    func codeFromHeader() -> Int? {
        let header = headerBuffer
        let headerString = String(data: header, encoding: .utf8) ?? ""
        let lines = headerString.split(separator: "\r\n")
        let firstLine = lines.first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        let codeString = parts[1]
        return Int(codeString)
    }

    func writeToDownstream(context: ChannelHandlerContext) {
        if !headerBuffer.isEmpty {
            let buffer = context.channel.allocator.buffer(bytes: headerBuffer)
            headerBuffer = Data()
            downstream.writeAndFlush(NIOAny(buffer), promise: nil)
        }
        if !bodyBuffer.isEmpty {
            let buffer = context.channel.allocator.buffer(bytes: bodyBuffer)
            bodyBuffer = Data()
            downstream.writeAndFlush(NIOAny(buffer), promise: nil)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        writeToDownstream(context: context)
        downstream.close(promise: nil)
    }
}

//
//  AIGateProxyHandler.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/15.
//

import Foundation
import NIO
import NIOSSL

class AIGateProxyHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    var remoteChannel: Channel?
    let upstream: AIGateUpstream
    let header: Data
    var bodyBuffer: Data
    let context: ChannelHandlerContext
    let group: EventLoopGroup

    init(upstream: AIGateUpstream, header: Data, body: Data, context: ChannelHandlerContext, group: EventLoopGroup) {
        self.upstream = upstream
        self.header = header
        bodyBuffer = body
        self.context = context
        self.group = group
    }

    func handlerAdded(context _: ChannelHandlerContext) {
        let tls = upstream.tls
        let host = upstream.host
        let port = upstream.port

        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                var ret = channel.pipeline.addHandlers([])
                if tls {
                    let sslContext = try! NIOSSLContext(configuration: .makeClientConfiguration())
                    let sslHandler = try! NIOSSLClientHandler(context: sslContext, serverHostname: host)
                    ret = channel.pipeline.addHandler(sslHandler)
                }
                let timeout = Int64(max(15, self.upstream.timeoutSeconds))
                ret = ret.flatMap {
                    channel.pipeline.addHandlers([
                        AIGateService.createIdleStateHandler(timeoutSeconds: timeout),
                        IdleTerminationHandler(),
                    ])
                }
                ret = ret.flatMap {
                    channel.pipeline.addHandler(AIGateProxySwitchHandler(proxyHandler: self))
                }
                return ret
            }

        bootstrap.connect(host: host, port: port).whenComplete { result in
            switch result {
            case let .success(remoteChannel):
                self.remoteChannel = remoteChannel
                var buffer = remoteChannel.allocator.buffer(capacity: self.header.count + self.bodyBuffer.count)
                buffer.writeBytes(self.header)
                buffer.writeBytes(self.bodyBuffer)
                self.bodyBuffer = Data()
                remoteChannel.writeAndFlush(buffer, promise: nil)
            case .failure:
                self.context.terminateChannel(reason: .endpointNotReachable)
            }
        }
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        if let remoteChannel {
            remoteChannel.writeAndFlush(buffer, promise: nil)
        } else {
            let readableBytes = buffer.readableBytes
            if let bytes = buffer.getBytes(at: buffer.readerIndex, length: readableBytes) {
                bodyBuffer.append(contentsOf: bytes)
            }
        }
    }

    func writeBack(buffer: ByteBuffer) {
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error _: Error) {
        remoteChannel?.close(mode: .all, promise: nil)
        context.close(mode: .all, promise: nil)
    }

    func channelInactive(context _: ChannelHandlerContext) {
        remoteChannel?.close(mode: .all, promise: nil)
    }
}

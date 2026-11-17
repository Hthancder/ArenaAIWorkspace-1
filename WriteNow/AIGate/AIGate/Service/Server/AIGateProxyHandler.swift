//
//  AIGateProxyHandler.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/15.
//

import Darwin
import Foundation
import NIO
import NIOSSL

class AIGateProxyHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private static let sharedSSLContext: NIOSSLContext? = try? NIOSSLContext(configuration: .makeClientConfiguration())

    var remoteChannel: Channel?
    let upstream: AIGateUpstream
    let header: Data
    var bodyBuffer: Data
    let context: ChannelHandlerContext
    let group: EventLoopGroup
    let requestStartNs: UInt64 = DispatchTime.now().uptimeNanoseconds
    var onFailureFallback: ((ServiceError) -> Bool)?
    var didTriggerFallback: Bool = false

    init(
        upstream: AIGateUpstream,
        header: Data,
        body: Data,
        context: ChannelHandlerContext,
        group: EventLoopGroup,
        onFailureFallback: ((ServiceError) -> Bool)? = nil
    ) {
        self.upstream = upstream
        self.header = header
        bodyBuffer = body
        self.context = context
        self.group = group
        self.onFailureFallback = onFailureFallback
    }

    private static func isIPAddress(_ host: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return host.withCString { cstr in
            inet_pton(AF_INET, cstr, &ipv4) == 1 || inet_pton(AF_INET6, cstr, &ipv6) == 1
        }
    }

    func handlerAdded(context _: ChannelHandlerContext) {
        let tls = upstream.tls
        let host = upstream.host
        let port = upstream.port
        let sniHost = Self.isIPAddress(host) ? nil : host

        let bootstrap = ClientBootstrap(group: context.eventLoop)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                var ret = channel.pipeline.addHandlers([])
                if tls {
                    do {
                        let sslContext: NIOSSLContext
                        if let cached = Self.sharedSSLContext {
                            sslContext = cached
                        } else {
                            sslContext = try NIOSSLContext(configuration: .makeClientConfiguration())
                        }
                        let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: sniHost)
                        ret = channel.pipeline.addHandler(sslHandler)
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
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
            self.context.eventLoop.execute {
                switch result {
                case let .success(remoteChannel):
                    self.remoteChannel = remoteChannel
                    var buffer = remoteChannel.allocator.buffer(capacity: self.header.count + self.bodyBuffer.count)
                    buffer.writeBytes(self.header)
                    buffer.writeBytes(self.bodyBuffer)
                    self.bodyBuffer = Data()
                    remoteChannel.writeAndFlush(buffer, promise: nil)
                case .failure:
                    self.handleFailureBeforeOutput(reason: .endpointNotReachable)
                }
            }
        }
    }

    func handleFailureBeforeOutput(reason: ServiceError) {
        let fallback = onFailureFallback
        onFailureFallback = nil
        if let fallback, fallback(reason) {
            didTriggerFallback = true
            remoteChannel?.close(mode: .all, promise: nil)
            remoteChannel = nil
            return
        }
        context.terminateChannel(reason: reason)
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

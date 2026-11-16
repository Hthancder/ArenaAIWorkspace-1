//
//  AIGateService.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/15.
//

import Foundation
import NIO
import NIOSSL

class AIGateService: Identifiable {
    var id: UUID = .init()
    var group: MultiThreadedEventLoopGroup
    var channel: Channel
    private var isShutDown = false

    public init() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        self.group = group
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                Self.channelInitializer(group: group, channel: channel)
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        do {
            channel = try bootstrap.bind(host: "127.0.0.1", port: aiGateServicePort).wait()
        } catch {
            try? group.syncShutdownGracefully()
            throw error
        }

        print("[*] server started and listen on \(AIGateConfiguration.listenURL.absoluteString)")
    }

    func wait() throws {
        try channel.closeFuture.wait()
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        try? channel.close(mode: .all).wait()
        try? group.syncShutdownGracefully()
    }

    deinit {
        if !isShutDown {
            channel.close(mode: .all, promise: nil)
            group.shutdownGracefully { _ in }
        }
    }
}

extension AIGateService {
    static func createIdleStateHandler(timeoutSeconds: Int64 = AIGateConfiguration.timeoutInterval) -> IdleStateHandler {
        IdleStateHandler(
            readTimeout: .seconds(timeoutSeconds),
            writeTimeout: .seconds(timeoutSeconds),
            allTimeout: .seconds(timeoutSeconds)
        )
    }

    static func channelInitializer(group: EventLoopGroup, channel: Channel) -> EventLoopFuture<Void> {
        var ret = channel.pipeline.addHandlers([])
        ret = channel.pipeline.addHandlers([
            createIdleStateHandler(),
            IdleTerminationHandler(),
        ])
        ret = channel.pipeline.addHandler(AIGateHandler(group: group))
        return ret
    }
}

//
//  AIGateUpstream.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/15.
//

import Foundation

struct AIGateUpstream {
    let url: URL
    let host: String
    let port: Int
    let tls: Bool
    let key: String
    let mid: String // model id
    let pathMode: Configuration.Endpoint.PathMode
    let customHeaders: [String: String]
    let timeoutSeconds: Int

    init(
        url: URL,
        host: String,
        port: Int,
        tls: Bool,
        key: String,
        mid: String,
        pathMode: Configuration.Endpoint.PathMode = .auto,
        customHeaders: [String: String] = [:],
        timeoutSeconds: Int = 60
    ) {
        self.url = url
        self.host = host
        self.port = port
        self.tls = tls
        self.key = key
        self.mid = mid
        self.pathMode = pathMode
        self.customHeaders = customHeaders
        self.timeoutSeconds = timeoutSeconds
    }
}

extension AIGateUpstream {
    init?() {
        self.init(endpointID: nil, modelOverride: nil)
    }

    init?(endpointID: UUID?, modelOverride: String?) {
        let cvm = Configuration.shared
        let matchedEndpoint: Configuration.Endpoint?
        if let endpointID {
            matchedEndpoint = cvm.allEndpointsSorted.first(where: { $0.id == endpointID }) ?? cvm.activatedEndpoint
        } else {
            matchedEndpoint = cvm.activatedEndpoint
        }
        guard let endpoint = matchedEndpoint else { return nil }

        guard let host = endpoint.url.host else { return nil }
        guard let scheme = endpoint.url.scheme else { return nil }

        let tls = scheme.lowercased() == "https"
        let port = endpoint.url.port ?? (tls ? 443 : 80)
        let key = endpoint.token
        let cleanOverride = (modelOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let model = cleanOverride.isEmpty ? endpoint.model : cleanOverride

        guard model.data(using: .utf8) != nil else { return nil }

        self.init(
            url: endpoint.url,
            host: host,
            port: port,
            tls: tls,
            key: key,
            mid: model,
            pathMode: endpoint.pathMode,
            customHeaders: endpoint.customHeaders,
            timeoutSeconds: max(15, endpoint.timeoutSeconds)
        )
    }
}

//
//  AIGateConfiguration.swift
//  AIGate
//
//  Created by Lessica on 2024/8/20.
//

import Foundation

#if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
    let aiGateServiceAddress = "0.0.0.0"
#else
    let aiGateServiceAddress = "127.0.0.1"
#endif

let aiGateServicePort = 5540

struct AIGateConfiguration {
    static var listenURL: URL = {
        var compos = URLComponents()
        compos.scheme = "http"
        compos.host = aiGateServiceAddress == "0.0.0.0" ? "127.0.0.1" : aiGateServiceAddress
        compos.port = aiGateServicePort
        return compos.url!
    }()

    static let timeoutInterval: Int64 = 35

    private init() {}
}

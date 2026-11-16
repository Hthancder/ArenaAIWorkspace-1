//
//  ServiceError.swift
//  AIGate
//
//  Created by Lessica on 2024/8/23.
//

import Foundation
import NIO

enum ServiceError: Error, Equatable {
    case serviceDisabled
    case endpointNotConfigured
    case endpointNotReachable
    case modelNotFound
    case invalidResponse
    case upstreamPassedError(code: Int, detail: String?)

    static var lastError: ServiceError? {
        didSet {
            NotificationCenter.default.post(name: .serviceErrorDidChange, object: lastError)
        }
    }

    var description: String {
        switch self {
        case .serviceDisabled:
            return NSLocalizedString("Service Disabled", comment: "")
        case .endpointNotConfigured:
            return NSLocalizedString("Endpoint Not Configured", comment: "")
        case .endpointNotReachable:
            return NSLocalizedString("Endpoint Not Reachable", comment: "")
        case .modelNotFound:
            return NSLocalizedString("Model Not Found", comment: "")
        case .invalidResponse:
            return NSLocalizedString("Invalid Response", comment: "")
        case let .upstreamPassedError(code, detail):
            let statusDesc = HTTPURLResponse.localizedString(forStatusCode: code).capitalized
            if let detail, !detail.isEmpty {
                return String(
                    format: NSLocalizedString("Endpoint Error: %d %@", comment: ""),
                    code,
                    "\(statusDesc) — \(detail)"
                )
            }
            return String(
                format: NSLocalizedString("Endpoint Error: %d %@", comment: ""),
                code,
                statusDesc
            )
        }
    }

    var rawCode: Int {
        switch self {
        case .serviceDisabled:
            return 503
        case .endpointNotConfigured:
            return 404
        case .endpointNotReachable:
            return 502
        case .modelNotFound:
            return 404
        case .invalidResponse:
            return 502
        case let .upstreamPassedError(code, _):
            return code
        }
    }
}

extension Notification.Name {
    static let serviceErrorDidChange = Notification.Name("wiki.qaq.AIGate.serviceErrorDidChange")
}

extension ChannelHandlerContext {
    func terminateChannel(reason: ServiceError? = nil) {
        if let reason {
            ServiceError.lastError = reason
            let detailMessage: String
            switch reason {
            case let .upstreamPassedError(code, detail):
                detailMessage = detail?.isEmpty == false ? detail! : reason.description
                let payloadDict: [String: Any] = [
                    "error": [
                        "message": detailMessage,
                        "type": "upstream_error",
                        "code": "\(code)",
                    ],
                ]
                if let jsonData = try? JSONSerialization.data(withJSONObject: payloadDict),
                   let jsonStr = String(data: jsonData, encoding: .utf8)
                {
                    let statusText = HTTPURLResponse.localizedString(forStatusCode: code).capitalized
                    let header = "HTTP/1.1 \(code) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(jsonData.count)\r\nConnection: close\r\n\r\n"
                    var buffer = channel.allocator.buffer(capacity: header.utf8.count + jsonData.count)
                    buffer.writeString(header)
                    buffer.writeString(jsonStr)
                    writeAndFlush(NIOAny(buffer)).whenComplete { _ in
                        self.close(mode: .all, promise: nil)
                    }
                    return
                }
            default:
                let payloadDict: [String: Any] = [
                    "error": [
                        "message": reason.description,
                        "type": "aigate_error",
                        "code": "\(reason.rawCode)",
                    ],
                ]
                if let jsonData = try? JSONSerialization.data(withJSONObject: payloadDict),
                   let jsonStr = String(data: jsonData, encoding: .utf8)
                {
                    let statusText = HTTPURLResponse.localizedString(forStatusCode: reason.rawCode).capitalized
                    let header = "HTTP/1.1 \(reason.rawCode) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(jsonData.count)\r\nConnection: close\r\n\r\n"
                    var buffer = channel.allocator.buffer(capacity: header.utf8.count + jsonData.count)
                    buffer.writeString(header)
                    buffer.writeString(jsonStr)
                    writeAndFlush(NIOAny(buffer)).whenComplete { _ in
                        self.close(mode: .all, promise: nil)
                    }
                    return
                }
            }
        }
        close(mode: .all, promise: nil)
    }
}

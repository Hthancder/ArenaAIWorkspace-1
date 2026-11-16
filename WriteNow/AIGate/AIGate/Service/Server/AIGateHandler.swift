//
//  AIGateHandler.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/15.
//

import Foundation
import NIO

class AIGateHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    var headerBuffer = Data()
    var bodyBuffer = Data()
    var isHeaderParsed = false
    var proxyHandler: AIGateProxyHandler?

    private var pendingLocalCommand: String?
    private var expectedBodyLength: Int = 0

    private var pendingProxyHeader: String?
    private var pendingProxyUpstream: AIGateUpstream?
    private var expectedProxyBodyLength: Int?
    private var pendingProxyIsChunked: Bool = false
    private let maxBufferedProxyBodyBytes = 16 * 1024 * 1024

    let group: EventLoopGroup

    init(group: EventLoopGroup) {
        self.group = group
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if let proxyHandler {
            proxyHandler.channelRead(context: context, data: data)
            return
        }

        var buffer = unwrapInboundIn(data)
        guard let bytes = buffer.readBytes(length: buffer.readableBytes) else {
            context.close(mode: .all, promise: nil)
            return
        }

        if let cmd = pendingLocalCommand {
            bodyBuffer.append(contentsOf: bytes)
            if bodyBuffer.count >= expectedBodyLength {
                let body = expectedBodyLength > 0 ? Data(bodyBuffer.prefix(expectedBodyLength)) : bodyBuffer
                pendingLocalCommand = nil
                bodyBuffer = Data()
                handleLocalActionCommand(cmd: cmd, body: body, context: context)
            }
            return
        }

        if let pendingHeader = pendingProxyHeader, let upstream = pendingProxyUpstream {
            bodyBuffer.append(contentsOf: bytes)
            if bodyBuffer.count > maxBufferedProxyBodyBytes {
                pendingProxyHeader = nil
                pendingProxyUpstream = nil
                expectedProxyBodyLength = nil
                pendingProxyIsChunked = false
                bodyBuffer = Data()
                context.terminateChannel(reason: .invalidResponse)
                return
            }

            if pendingProxyIsChunked {
                if let decoded = decodeChunkedBody(bodyBuffer) {
                    pendingProxyHeader = nil
                    pendingProxyUpstream = nil
                    expectedProxyBodyLength = nil
                    pendingProxyIsChunked = false
                    bodyBuffer = Data()
                    startProxying(
                        headerString: pendingHeader,
                        body: decoded,
                        hadBodyLengthHeader: true,
                        upstream: upstream,
                        context: context
                    )
                }
            } else if let expectedLen = expectedProxyBodyLength, bodyBuffer.count >= expectedLen {
                let body = Data(bodyBuffer.prefix(expectedLen))
                pendingProxyHeader = nil
                pendingProxyUpstream = nil
                expectedProxyBodyLength = nil
                pendingProxyIsChunked = false
                bodyBuffer = Data()
                startProxying(
                    headerString: pendingHeader,
                    body: body,
                    hadBodyLengthHeader: true,
                    upstream: upstream,
                    context: context
                )
            }
            return
        }

        if !isHeaderParsed {
            headerBuffer.append(contentsOf: bytes)
        } else {
            bodyBuffer.append(contentsOf: bytes)
            return
        }

        let delimiter = "\r\n\r\n".data(using: .utf8)!
        guard let range = headerBuffer.range(of: delimiter) else {
            if headerBuffer.count > 64 * 1024 {
                context.close(mode: .all, promise: nil)
            }
            return
        }

        let headerData = headerBuffer.subdata(in: 0 ..< range.lowerBound)
        bodyBuffer = headerBuffer.subdata(in: range.upperBound ..< headerBuffer.count)
        headerBuffer = Data()
        isHeaderParsed = true

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            context.close(mode: .all, promise: nil)
            return
        }

        if let localAction = parseLocalActionCommand(from: headerString) {
            let contentLength = parseContentLength(from: headerString) ?? 0
            if bodyBuffer.count >= contentLength {
                let body = contentLength > 0 ? Data(bodyBuffer.prefix(contentLength)) : bodyBuffer
                bodyBuffer = Data()
                handleLocalActionCommand(cmd: localAction, body: body, context: context)
            } else {
                pendingLocalCommand = localAction
                expectedBodyLength = contentLength
            }
            return
        }

        if checkForMetricsEndpoint(from: headerString, context: context) {
            return
        }

        if !Configuration.shared.isEnabled {
            context.terminateChannel(reason: .serviceDisabled)
            return
        }

        guard let upstream = AIGateUpstream() else {
            context.terminateChannel(reason: .endpointNotConfigured)
            return
        }

        if upstream.mid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.terminateChannel(reason: .modelNotFound)
            return
        }

        let contentLength = parseContentLength(from: headerString)
        let isChunked = isChunkedTransferEncoding(in: headerString)

        if let contentLength, contentLength > 0 {
            if bodyBuffer.count >= contentLength {
                let body = Data(bodyBuffer.prefix(contentLength))
                bodyBuffer = Data()
                startProxying(
                    headerString: headerString,
                    body: body,
                    hadBodyLengthHeader: true,
                    upstream: upstream,
                    context: context
                )
            } else {
                pendingProxyHeader = headerString
                pendingProxyUpstream = upstream
                expectedProxyBodyLength = contentLength
                pendingProxyIsChunked = false
            }
            return
        }

        if isChunked {
            if let decoded = decodeChunkedBody(bodyBuffer) {
                bodyBuffer = Data()
                startProxying(
                    headerString: headerString,
                    body: decoded,
                    hadBodyLengthHeader: true,
                    upstream: upstream,
                    context: context
                )
            } else {
                pendingProxyHeader = headerString
                pendingProxyUpstream = upstream
                expectedProxyBodyLength = nil
                pendingProxyIsChunked = true
            }
            return
        }

        let body = bodyBuffer
        bodyBuffer = Data()
        startProxying(
            headerString: headerString,
            body: body,
            hadBodyLengthHeader: contentLength != nil,
            upstream: upstream,
            context: context
        )
    }

    private func startProxying(
        headerString: String,
        body: Data,
        hadBodyLengthHeader: Bool,
        upstream: AIGateUpstream,
        context: ChannelHandlerContext
    ) {
        let finalBody = rewriteRequestBodyIfNeeded(body, with: upstream)
        let bodyLengthToSend: Int? = (hadBodyLengthHeader || !finalBody.isEmpty) ? finalBody.count : nil

        guard let patchedHeader = patchHeaderValues(headerString, with: upstream, bodyLength: bodyLengthToSend) else {
            context.close(mode: .all, promise: nil)
            return
        }
        guard let patchedHeaderData = patchedHeader.data(using: .utf8) else {
            context.close(mode: .all, promise: nil)
            return
        }

        let proxy = AIGateProxyHandler(
            upstream: upstream,
            header: patchedHeaderData,
            body: finalBody,
            context: context,
            group: context.eventLoop
        )
        proxyHandler = proxy
        proxy.handlerAdded(context: context)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if let proxyHandler {
            proxyHandler.errorCaught(context: context, error: error)
        } else {
            context.close(mode: .all, promise: nil)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        if let proxyHandler {
            proxyHandler.channelInactive(context: context)
        }
    }

    private func sendJSONResponse(_ jsonData: Data, statusCode: Int = 200, statusText: String = "OK", context: ChannelHandlerContext) {
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let response = "HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(jsonData.count)\r\nConnection: close\r\n\r\n\(jsonString)"
        var buffer = context.channel.allocator.buffer(capacity: response.utf8.count)
        buffer.writeString(response)
        context.writeAndFlush(NIOAny(buffer)).whenComplete { _ in
            context.close(mode: .all, promise: nil)
        }
    }

    private func sendJSONDictionary(_ dict: [String: Any], statusCode: Int = 200, statusText: String = "OK", context: ChannelHandlerContext) {
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{}".utf8)
        sendJSONResponse(data, statusCode: statusCode, statusText: statusText, context: context)
    }

    private func parseRequestLineAndHeaders(from headerString: String) -> (method: String, uri: String, headers: [(String, String)])? {
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let reqParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard reqParts.count >= 2 else { return nil }
        let method = String(reqParts[0])
        let uri = String(reqParts[1])
        var headers: [(String, String)] = []
        for line in lines.dropFirst() {
            guard !line.isEmpty, let colonIdx = line.firstIndex(of: ":") else { continue }
            let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces)
            let val = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
            headers.append((key, val))
        }
        return (method, uri, headers)
    }

    private func parseContentLength(from headerString: String) -> Int? {
        guard let parsed = parseRequestLineAndHeaders(from: headerString) else { return nil }
        for (key, value) in parsed.headers where key.caseInsensitiveCompare("Content-Length") == .orderedSame {
            return Int(value)
        }
        return nil
    }

    private func parseLocalActionCommand(from headerString: String) -> String? {
        guard let parsed = parseRequestLineAndHeaders(from: headerString) else { return nil }
        guard let url = URL(string: "http://localhost\(parsed.uri)"),
              url.path == "/action",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let cmd = comps.queryItems?.first(where: { $0.name == "command" })?.value
        else {
            return nil
        }

        if cmd == "reload" || cmd == "terminate" || cmd == "ping" {
            var secretMatches = false
            for (key, val) in parsed.headers where
                key.caseInsensitiveCompare("X-AIGate-Secret") == .orderedSame
                || key.caseInsensitiveCompare("X-Service-Secret") == .orderedSame
            {
                if val == Configuration.shared.serviceSecret {
                    secretMatches = true
                } else {
                    Configuration.shared.reloadServiceSecretFromDisk()
                    secretMatches = (val == Configuration.shared.serviceSecret)
                }
            }
            guard secretMatches else { return nil }
        }
        return parsed.uri
    }

    private func handleLocalActionCommand(cmd fullURI: String, body: Data, context: ChannelHandlerContext) {
        guard let url = URL(string: "http://localhost\(fullURI)"),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let cmd = comps.queryItems?.first(where: { $0.name == "command" })?.value
        else {
            sendJSONDictionary(["error": "Invalid command"], statusCode: 400, statusText: "Bad Request", context: context)
            return
        }

        switch cmd {
        case "ping":
            sendJSONDictionary(["status": "ok"], context: context)

        case "reload":
            Configuration.shared.reloadValueFromSystem()
            sendJSONDictionary(["status": "ok"], context: context)

        case "terminate":
            sendJSONDictionary(["status": "ok"], context: context)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15) {
                exit(EXIT_SUCCESS)
            }

        case "switch_endpoint":
            if let uuidString = comps.queryItems?.first(where: { $0.name == "id" })?.value,
               let uuid = UUID(uuidString: uuidString),
               Configuration.shared.hasEndpointWithID(uuid)
            {
                Configuration.shared.activatedEndpointID = uuid
                Configuration.shared.saveNow()
                Configuration.shared.reloadValueFromSystem()
                sendJSONDictionary(["status": "ok"], context: context)
            } else {
                sendJSONDictionary(["error": "Endpoint not found"], statusCode: 404, statusText: "Not Found", context: context)
            }

        case "set":
            if let uuidString = comps.queryItems?.first(where: { $0.name == "id" })?.value,
               let uuid = UUID(uuidString: uuidString),
               Configuration.shared.hasEndpointWithID(uuid)
            {
                Configuration.shared.activatedEndpointID = uuid
                Configuration.shared.saveNow()
                Configuration.shared.reloadValueFromSystem()
                sendJSONDictionary(["status": "ok"], context: context)
            } else {
                sendJSONDictionary(["error": "Endpoint not found"], statusCode: 404, statusText: "Not Found", context: context)
            }

        case "upsert_endpoint":
            handleUpsertEndpoint(body: body, context: context)

        case "delete_endpoint":
            handleDeleteEndpoint(body: body, context: context)

        case "fetch_models":
            handleFetchModels(body: body, context: context)

        case "test_endpoint":
            handleTestEndpoint(body: body, context: context)

        case "record_quick_prompt":
            if let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let prompt = dict["prompt"] as? String
            {
                Configuration.shared.recordQuickPrompt(prompt)
            }
            sendJSONDictionary(["status": "ok"], context: context)

        default:
            sendJSONDictionary(["error": "Unsupported command"], statusCode: 400, statusText: "Bad Request", context: context)
        }
    }

    private func handleUpsertEndpoint(body: Data, context: ChannelHandlerContext) {
        guard let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let rawURL = dict["url"] as? String,
              let normalizedURL = EndpointURLHelper.normalizeBaseURL(rawURL)
        else {
            sendJSONDictionary(["error": "Invalid endpoint URL"], statusCode: 400, statusText: "Bad Request", context: context)
            return
        }

        let id = (dict["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let existing = Configuration.shared.endpoint(for: id)

        let name = (dict["name"] as? String) ?? existing?.name ?? ""
        let incomingToken = dict["token"] as? String
        let resolvedToken: String
        if let incomingToken, incomingToken != "[********]" {
            resolvedToken = incomingToken
        } else {
            resolvedToken = existing?.token ?? ""
        }
        let model = ((dict["model"] as? String) ?? existing?.model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pathModeRaw = (dict["pathMode"] as? String) ?? existing?.pathMode.rawValue ?? Configuration.Endpoint.PathMode.auto.rawValue
        let pathMode = Configuration.Endpoint.PathMode(rawValue: pathModeRaw) ?? .auto
        let customHeaders = (dict["customHeaders"] as? [String: String]) ?? existing?.customHeaders ?? [:]
        let useStreaming = (dict["useStreaming"] as? Bool) ?? existing?.useStreaming ?? true
        let timeoutSeconds = (dict["timeoutSeconds"] as? Int) ?? existing?.timeoutSeconds ?? 60
        let activate = (dict["activate"] as? Bool) ?? true

        let endpoint = Configuration.Endpoint(
            id: id,
            create: existing?.create ?? Date(),
            name: name,
            url: normalizedURL,
            token: resolvedToken,
            model: model,
            pathMode: pathMode,
            customHeaders: customHeaders,
            useStreaming: useStreaming,
            timeoutSeconds: max(15, timeoutSeconds)
        )
        Configuration.shared.upsert(endpoint, activate: activate)

        let payload = Configuration.shared.buildRuntimeConfigPayload(redactTokens: false)
        let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
        sendJSONResponse(data, context: context)
    }

    private func handleDeleteEndpoint(body: Data, context: ChannelHandlerContext) {
        guard let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString)
        else {
            sendJSONDictionary(["error": "Invalid endpoint ID"], statusCode: 400, statusText: "Bad Request", context: context)
            return
        }
        Configuration.shared.removeEndpoint(id: id)
        let payload = Configuration.shared.buildRuntimeConfigPayload(redactTokens: false)
        let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
        sendJSONResponse(data, context: context)
    }

    private func handleFetchModels(body: Data, context: ChannelHandlerContext) {
        guard let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let rawURL = dict["url"] as? String,
              let baseURL = EndpointURLHelper.normalizeBaseURL(rawURL)
        else {
            sendJSONDictionary(["models": [], "error": "Invalid URL"], statusCode: 400, statusText: "Bad Request", context: context)
            return
        }
        let token = (dict["token"] as? String) ?? ""
        let pathMode = Configuration.Endpoint.PathMode(rawValue: (dict["pathMode"] as? String) ?? "auto") ?? .auto
        let customHeaders = (dict["customHeaders"] as? [String: String]) ?? [:]

        Task {
            let result = await EndpointNetworkHelper.fetchModels(baseURL: baseURL, token: token, pathMode: pathMode, customHeaders: customHeaders)
            context.eventLoop.execute {
                switch result {
                case let .success(models):
                    self.sendJSONDictionary(["models": models], context: context)
                case let .failure(err):
                    self.sendJSONDictionary(["models": [], "error": err.localizedDescription], context: context)
                }
            }
        }
    }

    private func handleTestEndpoint(body: Data, context: ChannelHandlerContext) {
        guard let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let rawURL = dict["url"] as? String,
              let baseURL = EndpointURLHelper.normalizeBaseURL(rawURL)
        else {
            sendJSONDictionary(["ok": false, "message": "Invalid URL"], statusCode: 400, statusText: "Bad Request", context: context)
            return
        }
        let token = (dict["token"] as? String) ?? ""
        let model = ((dict["model"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pathMode = Configuration.Endpoint.PathMode(rawValue: (dict["pathMode"] as? String) ?? "auto") ?? .auto
        let customHeaders = (dict["customHeaders"] as? [String: String]) ?? [:]
        let timeout = max(10, (dict["timeoutSeconds"] as? Int) ?? 30)

        Task {
            let res = await EndpointNetworkHelper.testChatEndpoint(
                baseURL: baseURL,
                token: token,
                model: model,
                pathMode: pathMode,
                customHeaders: customHeaders,
                timeoutSeconds: timeout
            )
            var payload: [String: Any] = [
                "ok": res.ok,
                "latencyMs": res.latencyMs,
                "message": res.message,
            ]
            if let code = res.statusCode {
                payload["statusCode"] = code
            }
            context.eventLoop.execute {
                self.sendJSONDictionary(payload, context: context)
            }
        }
    }

    private func checkForMetricsEndpoint(from headerString: String, context: ChannelHandlerContext) -> Bool {
        guard let parsed = parseRequestLineAndHeaders(from: headerString),
              parsed.method == "GET",
              let url = URL(string: "http://localhost\(parsed.uri)"),
              url.path == "/metrics",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let query = comps.queryItems?.first(where: { $0.name == "query" })?.value
        else {
            return false
        }

        switch query {
        case "status":
            let payload: [String: String] = [
                "status": Configuration.shared.isEnabled ? "enabled" : "disabled",
                "error": ServiceError.lastError?.description ?? "",
            ]
            let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
            sendJSONResponse(data, context: context)
            return true

        case "last_error":
            let payload: [String: String] = [
                "last_error": ServiceError.lastError?.description ?? "",
            ]
            let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
            sendJSONResponse(data, context: context)
            return true

        case "model":
            let payload = Configuration.shared.buildRuntimeConfigPayload(redactTokens: true)
            let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
            sendJSONResponse(data, context: context)
            return true

        case "config":
            let redact = Configuration.shared.appSettings.maskEndpointKeys
            let payload = Configuration.shared.buildRuntimeConfigPayload(redactTokens: redact)
            let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
            sendJSONResponse(data, context: context)
            return true

        default:
            return false
        }
    }

    private func isChunkedTransferEncoding(in headerString: String) -> Bool {
        guard let parsed = parseRequestLineAndHeaders(from: headerString) else { return false }
        for (key, value) in parsed.headers where key.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame {
            if value.lowercased().contains("chunked") {
                return true
            }
        }
        return false
    }

    private func decodeChunkedBody(_ data: Data) -> Data? {
        let crlf = Data("\r\n".utf8)
        var offset = 0
        var decoded = Data()

        while offset < data.count {
            guard let lineEndRange = data.range(of: crlf, options: [], in: offset ..< data.count) else {
                return nil
            }
            let sizeLineData = data.subdata(in: offset ..< lineEndRange.lowerBound)
            guard let sizeLine = String(data: sizeLineData, encoding: .utf8) else {
                return nil
            }
            let hexPart = sizeLine.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let chunkSize = Int(hexPart, radix: 16) else {
                return nil
            }
            offset = lineEndRange.upperBound
            if chunkSize == 0 {
                // Terminating chunk: expect "\r\n" (no trailers) or "\r\n\r\n" after trailers
                if offset + 2 <= data.count, data.subdata(in: offset ..< offset + 2) == crlf {
                    return decoded
                }
                let doubleCRLF = Data("\r\n\r\n".utf8)
                if data.range(of: doubleCRLF, options: [], in: offset ..< data.count) != nil {
                    return decoded
                }
                return nil
            }
            guard offset + chunkSize + 2 <= data.count else {
                return nil
            }
            decoded.append(data.subdata(in: offset ..< offset + chunkSize))
            offset += chunkSize + 2
        }
        return nil
    }

    private func rewriteRequestBodyIfNeeded(_ body: Data, with upstream: AIGateUpstream) -> Data {
        guard !body.isEmpty else { return body }
        let targetModel = upstream.mid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetModel.isEmpty else { return body }

        guard var jsonObject = (try? JSONSerialization.jsonObject(with: body, options: [.mutableContainers])) as? [String: Any] else {
            return body
        }

        let currentModel = (jsonObject["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if currentModel.isEmpty || currentModel == "user_activated_model" {
            jsonObject["model"] = targetModel
            if let rewritten = try? JSONSerialization.data(withJSONObject: jsonObject, options: []) {
                return rewritten
            }
        }
        return body
    }

    func patchHeaderValues(_ headerString: String, with upstream: AIGateUpstream, bodyLength: Int? = nil) -> String? {
        let headerLines = headerString.components(separatedBy: "\r\n")
        guard !headerLines.isEmpty else { return nil }

        let requestLineParts = headerLines[0].components(separatedBy: " ")
        guard requestLineParts.count >= 3 else { return nil }

        let method = requestLineParts[0]
        let originalURI = requestLineParts[1]
        let httpVersion = requestLineParts[2]

        let rewrittenURI = EndpointURLHelper.buildUpstreamURI(
            baseURL: upstream.url,
            requestURI: originalURI,
            pathMode: upstream.pathMode
        )

        var newLines: [String] = []
        newLines.append("\(method) \(rewrittenURI) \(httpVersion)")

        let customHeaderKeysLower = Set(upstream.customHeaders.keys.map { $0.lowercased() })

        for line in headerLines.dropFirst() {
            guard !line.isEmpty else { continue }
            guard let colonIndex = line.firstIndex(of: ":") else {
                newLines.append(line)
                continue
            }
            let key = line[..<colonIndex].trimmingCharacters(in: .whitespaces)
            let lowerKey = key.lowercased()

            if lowerKey == "host"
                || lowerKey == "authorization"
                || lowerKey == "origin"
                || lowerKey == "referer"
                || lowerKey == "accept-encoding"
                || lowerKey == "connection"
                || lowerKey == "proxy-connection"
                || lowerKey == "keep-alive"
                || lowerKey == "transfer-encoding"
                || (bodyLength != nil && lowerKey == "content-length")
                || customHeaderKeysLower.contains(lowerKey)
            {
                continue
            }
            newLines.append(line)
        }

        let isDefaultPort = (upstream.tls && upstream.port == 443) || (!upstream.tls && upstream.port == 80)
        let hostHeaderValue = isDefaultPort ? upstream.host : "\(upstream.host):\(upstream.port)"
        newLines.append("Host: \(hostHeaderValue)")
        newLines.append("Accept-Encoding: identity")
        newLines.append("Connection: close")
        if let bodyLength {
            newLines.append("Content-Length: \(bodyLength)")
        }

        if !upstream.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newLines.append("Authorization: Bearer \(upstream.key)")
        }

        for (headerKey, headerVal) in upstream.customHeaders {
            let trimmedKey = headerKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else { continue }
            newLines.append("\(trimmedKey): \(headerVal)")
        }

        return newLines.joined(separator: "\r\n") + "\r\n\r\n"
    }
}


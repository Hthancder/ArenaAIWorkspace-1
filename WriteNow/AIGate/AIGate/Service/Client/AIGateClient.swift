//
//  AIGateClient.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/15.
//

import Foundation

class AIGateClient {
    enum Command: String, CaseIterable, Codable {
        case ping
        case reload
    }

    enum CommandHeader: String {
        case exec = "X-Service-Command-Exec"
        case sect = "X-Service-Secret"
        case gateSecret = "X-AIGate-Secret"
    }

    typealias CommandCompletion = (Data?, Error?) -> Void

    static func executeCommand(_ command: Command, secret overrideSecret: String? = nil, completion: CommandCompletion? = nil) {
        var comps = URLComponents(url: AIGateConfiguration.listenURL, resolvingAgainstBaseURL: false)!
        comps.path = "/action"
        comps.queryItems = [URLQueryItem(name: "command", value: command.rawValue)]

        var request = URLRequest(
            url: comps.url ?? AIGateConfiguration.listenURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 5
        )
        request.httpMethod = "GET"
        request.addValue(command.rawValue, forHTTPHeaderField: CommandHeader.exec.rawValue)
        let secret = overrideSecret ?? GlobalStorage.shared.readDirectValue(forKey: "ServiceSecret") ?? ""
        request.addValue(secret, forHTTPHeaderField: CommandHeader.sect.rawValue)
        request.addValue(secret, forHTTPHeaderField: CommandHeader.gateSecret.rawValue)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error { print("[*] failed to execute command: \(error)") }
            completion?(data, error)
        }.resume()
    }
}

extension AIGateClient.Command {
    func execute() {
        switch self {
        case .ping: break
        case .reload: Configuration.shared.reloadValueFromSystem()
        }
    }
}

enum EndpointNetworkHelper {
    struct NetworkError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func fetchModels(
        baseURL: URL,
        token: String,
        pathMode: Configuration.Endpoint.PathMode = .auto,
        customHeaders: [String: String] = [:]
    ) async -> Result<[String], Error> {
        let candidates = EndpointURLHelper.candidateModelsURLs(baseURL: baseURL, pathMode: pathMode)
        guard !candidates.isEmpty else {
            return .failure(NetworkError(message: "Invalid base URL"))
        }

        var lastError: Error = NetworkError(message: "Unable to fetch models")
        for url in candidates {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            for (k, v) in customHeaders where !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                request.setValue(v, forHTTPHeaderField: k)
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }

                if (200 ..< 300).contains(http.statusCode) {
                    let parsed = parseModelList(from: data)
                    if !parsed.isEmpty {
                        return .success(parsed)
                    }
                    lastError = NetworkError(message: "HTTP \(http.statusCode): Empty model list returned")
                } else {
                    let msg = parseErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
                    lastError = NetworkError(message: "HTTP \(http.statusCode): \(msg)")
                }
            } catch {
                lastError = error
            }
        }
        return .failure(lastError)
    }

    static func testChatEndpoint(
        baseURL: URL,
        token: String,
        model: String,
        pathMode: Configuration.Endpoint.PathMode = .auto,
        customHeaders: [String: String] = [:],
        timeoutSeconds: Int = 30
    ) async -> (ok: Bool, statusCode: Int?, latencyMs: Int, message: String) {
        guard let url = EndpointURLHelper.chatCompletionsURL(baseURL: baseURL, pathMode: pathMode) else {
            return (false, nil, 0, "Invalid chat completions URL")
        }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            return (false, nil, 0, "Model ID is empty")
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: TimeInterval(max(10, timeoutSeconds)))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in customHeaders where !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let bodyObj: [String: Any] = [
            "model": trimmedModel,
            "messages": [
                ["role": "user", "content": "Reply with OK"],
            ],
            "max_tokens": 16,
            "stream": false,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyObj)

        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
            guard let http = response as? HTTPURLResponse else {
                return (false, nil, latencyMs, "Invalid HTTP response")
            }
            if (200 ..< 300).contains(http.statusCode) {
                if let reply = parseChatReplySnippet(from: data) {
                    return (true, http.statusCode, latencyMs, "HTTP \(http.statusCode) (\(latencyMs)ms): \(reply)")
                }
                return (true, http.statusCode, latencyMs, "HTTP \(http.statusCode) OK (\(latencyMs)ms)")
            } else {
                let errMsg = parseErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
                return (false, http.statusCode, latencyMs, "HTTP \(http.statusCode): \(errMsg)")
            }
        } catch {
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
            return (false, nil, latencyMs, error.localizedDescription)
        }
    }

    private static func parseModelList(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var ids: [String] = []
        if let dict = json as? [String: Any] {
            if let dataArr = dict["data"] as? [[String: Any]] {
                ids = dataArr.compactMap { $0["id"] as? String ?? $0["name"] as? String }
            } else if let modelsArr = dict["models"] as? [[String: Any]] {
                ids = modelsArr.compactMap { item in
                    if let id = item["id"] as? String { return id }
                    if let name = item["name"] as? String {
                        return name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
                    }
                    return nil
                }
            } else if let strArr = dict["models"] as? [String] {
                ids = strArr
            }
        } else if let arr = json as? [[String: Any]] {
            ids = arr.compactMap { $0["id"] as? String ?? $0["name"] as? String }
        } else if let strArr = json as? [String] {
            ids = strArr
        }
        return Array(Set(ids)).sorted()
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? nil : String(raw.prefix(200))
        }
        if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
            return msg
        }
        if let msg = obj["message"] as? String { return msg }
        if let detail = obj["detail"] as? String { return detail }
        if let errStr = obj["error"] as? String { return errStr }
        return nil
    }

    private static func parseChatReplySnippet(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(80))
    }
}

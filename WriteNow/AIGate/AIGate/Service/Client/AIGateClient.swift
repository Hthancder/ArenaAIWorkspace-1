//
//  AIGateClient.swift
//  AIGate
//
//  Created by Lessica on 2024/8/20.
//

import Foundation

class AIGateClient {
    enum Command: String {
        case reload
        case test
        case reset
        case kill
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
    func execute(completion: AIGateClient.CommandCompletion? = nil) {
        AIGateClient.executeCommand(self, completion: completion)
    }

    func executeAndWait() {
        let semaphore = DispatchSemaphore(value: 0)
        execute { _, _ in
            semaphore.signal()
        }
        semaphore.wait()
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
        customHeaders: [String: String] = [:],
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        let candidates = EndpointURLHelper.candidateModelsURLs(baseURL: baseURL, pathMode: pathMode)
        guard !candidates.isEmpty else {
            DispatchQueue.main.async {
                completion(.failure(NetworkError(message: "Invalid base URL")))
            }
            return
        }

        tryFetchCandidate(
            candidates: candidates,
            index: 0,
            token: token,
            customHeaders: customHeaders,
            lastError: NetworkError(message: "Unable to fetch models"),
            completion: completion
        )
    }

    private static func tryFetchCandidate(
        candidates: [URL],
        index: Int,
        token: String,
        customHeaders: [String: String],
        lastError: Error,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard index < candidates.count else {
            DispatchQueue.main.async {
                completion(.failure(lastError))
            }
            return
        }

        let url = candidates[index]
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in customHeaders where !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(v, forHTTPHeaderField: k)
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                tryFetchCandidate(
                    candidates: candidates,
                    index: index + 1,
                    token: token,
                    customHeaders: customHeaders,
                    lastError: error,
                    completion: completion
                )
                return
            }

            guard let http = response as? HTTPURLResponse, let data else {
                tryFetchCandidate(
                    candidates: candidates,
                    index: index + 1,
                    token: token,
                    customHeaders: customHeaders,
                    lastError: lastError,
                    completion: completion
                )
                return
            }

            if (200 ..< 300).contains(http.statusCode) {
                let parsed = parseModelList(from: data)
                if !parsed.isEmpty {
                    DispatchQueue.main.async {
                        completion(.success(parsed))
                    }
                    return
                }
                let err = NetworkError(message: "HTTP \(http.statusCode): Empty model list returned")
                tryFetchCandidate(
                    candidates: candidates,
                    index: index + 1,
                    token: token,
                    customHeaders: customHeaders,
                    lastError: err,
                    completion: completion
                )
            } else {
                let msg = parseErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
                let err = NetworkError(message: "HTTP \(http.statusCode): \(msg)")
                tryFetchCandidate(
                    candidates: candidates,
                    index: index + 1,
                    token: token,
                    customHeaders: customHeaders,
                    lastError: err,
                    completion: completion
                )
            }
        }.resume()
    }

    static func testChatEndpoint(
        baseURL: URL,
        token: String,
        model: String,
        pathMode: Configuration.Endpoint.PathMode = .auto,
        customHeaders: [String: String] = [:],
        timeoutSeconds: Int = 30,
        completion: @escaping (_ ok: Bool, _ statusCode: Int?, _ latencyMs: Int, _ message: String) -> Void
    ) {
        guard let url = EndpointURLHelper.chatCompletionsURL(baseURL: baseURL, pathMode: pathMode) else {
            DispatchQueue.main.async {
                completion(false, nil, 0, "Invalid chat completions URL")
            }
            return
        }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            DispatchQueue.main.async {
                completion(false, nil, 0, "Model ID is empty")
            }
            return
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
        URLSession.shared.dataTask(with: request) { data, response, error in
            let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
            if let error {
                DispatchQueue.main.async {
                    completion(false, nil, latencyMs, error.localizedDescription)
                }
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                DispatchQueue.main.async {
                    completion(false, nil, latencyMs, "Invalid HTTP response")
                }
                return
            }
            if (200 ..< 300).contains(http.statusCode) {
                let msg: String
                if let reply = parseChatReplySnippet(from: data) {
                    msg = "HTTP \(http.statusCode) (\(latencyMs)ms): \(reply)"
                } else {
                    msg = "HTTP \(http.statusCode) OK (\(latencyMs)ms)"
                }
                DispatchQueue.main.async {
                    completion(true, http.statusCode, latencyMs, msg)
                }
            } else {
                let errMsg = parseErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
                DispatchQueue.main.async {
                    completion(false, http.statusCode, latencyMs, "HTTP \(http.statusCode): \(errMsg)")
                }
            }
        }.resume()
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

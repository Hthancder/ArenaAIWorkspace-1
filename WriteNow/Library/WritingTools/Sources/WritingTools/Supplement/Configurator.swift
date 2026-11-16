//
//  Configurator.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

import Combine
import Foundation
import OpenAI
import WritingToolsLocalizable

public struct EndpointItem: Codable, Identifiable, Equatable, Hashable {
    public enum PathMode: String, Codable, CaseIterable, Hashable {
        case auto
        case raw

        public var displayName: String {
            switch self {
            case .auto: return "Auto (/v1 smart)"
            case .raw: return "Raw (as entered)"
            }
        }
    }

    public let id: UUID
    public let create: Date
    public var name: String
    public var url: URL
    public var token: String
    public var model: String
    public var pathMode: PathMode
    public var customHeaders: [String: String]
    public var useStreaming: Bool
    public var timeoutSeconds: Int

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let host = url.host, !host.isEmpty {
            if let port = url.port { return "\(host):\(port)" }
            return host
        }
        return url.absoluteString
    }

    public var shortModelName: String {
        model.components(separatedBy: "/").last?.components(separatedBy: ":").first ?? model
    }

    public init(
        id: UUID = UUID(),
        create: Date = Date(),
        name: String = "",
        url: URL,
        token: String = "",
        model: String = "",
        pathMode: PathMode = .auto,
        customHeaders: [String: String] = [:],
        useStreaming: Bool = true,
        timeoutSeconds: Int = 60
    ) {
        self.id = id
        self.create = create
        self.name = name
        self.url = url
        self.token = token
        self.model = model
        self.pathMode = pathMode
        self.customHeaders = customHeaders
        self.useStreaming = useStreaming
        self.timeoutSeconds = timeoutSeconds
    }

    enum CodingKeys: String, CodingKey {
        case id, create, name, url, token, model, pathMode, customHeaders, useStreaming, timeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        create = try c.decodeIfPresent(Date.self, forKey: .create) ?? Date()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try c.decode(URL.self, forKey: .url)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        pathMode = try c.decodeIfPresent(PathMode.self, forKey: .pathMode) ?? .auto
        customHeaders = try c.decodeIfPresent([String: String].self, forKey: .customHeaders) ?? [:]
        useStreaming = try c.decodeIfPresent(Bool.self, forKey: .useStreaming) ?? true
        timeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 60
    }
}

public struct RuntimeSettings: Codable, Equatable {
    public var menuTitle: String
    public var globalSystemPrompt: String
    public var useFewShotExamples: Bool
    public var stripThinkingTags: Bool
    public var streamingEnabled: Bool
    public var requestTimeout: Int
    public var gridColumns: Int
    public var popoverSizePreset: String
    public var animatedBackground: Bool
    public var autoSelectAllIfEmpty: Bool
    public var maskEndpointKeys: Bool
    public var recentCustomPrompts: [String]

    public static let `default` = RuntimeSettings(
        menuTitle: "Write Now",
        globalSystemPrompt: "",
        useFewShotExamples: true,
        stripThinkingTags: true,
        streamingEnabled: true,
        requestTimeout: 60,
        gridColumns: 2,
        popoverSizePreset: "standard",
        animatedBackground: true,
        autoSelectAllIfEmpty: true,
        maskEndpointKeys: false,
        recentCustomPrompts: []
    )

    enum CodingKeys: String, CodingKey {
        case menuTitle, globalSystemPrompt, useFewShotExamples, stripThinkingTags
        case streamingEnabled, requestTimeout, gridColumns, popoverSizePreset
        case animatedBackground, autoSelectAllIfEmpty, maskEndpointKeys, recentCustomPrompts
    }

    public init(
        menuTitle: String = "Write Now",
        globalSystemPrompt: String = "",
        useFewShotExamples: Bool = true,
        stripThinkingTags: Bool = true,
        streamingEnabled: Bool = true,
        requestTimeout: Int = 60,
        gridColumns: Int = 2,
        popoverSizePreset: String = "standard",
        animatedBackground: Bool = true,
        autoSelectAllIfEmpty: Bool = true,
        maskEndpointKeys: Bool = false,
        recentCustomPrompts: [String] = []
    ) {
        self.menuTitle = menuTitle
        self.globalSystemPrompt = globalSystemPrompt
        self.useFewShotExamples = useFewShotExamples
        self.stripThinkingTags = stripThinkingTags
        self.streamingEnabled = streamingEnabled
        self.requestTimeout = requestTimeout
        self.gridColumns = gridColumns
        self.popoverSizePreset = popoverSizePreset
        self.animatedBackground = animatedBackground
        self.autoSelectAllIfEmpty = autoSelectAllIfEmpty
        self.maskEndpointKeys = maskEndpointKeys
        self.recentCustomPrompts = recentCustomPrompts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menuTitle = try c.decodeIfPresent(String.self, forKey: .menuTitle) ?? "Write Now"
        globalSystemPrompt = try c.decodeIfPresent(String.self, forKey: .globalSystemPrompt) ?? ""
        useFewShotExamples = try c.decodeIfPresent(Bool.self, forKey: .useFewShotExamples) ?? true
        stripThinkingTags = try c.decodeIfPresent(Bool.self, forKey: .stripThinkingTags) ?? true
        streamingEnabled = try c.decodeIfPresent(Bool.self, forKey: .streamingEnabled) ?? true
        requestTimeout = try c.decodeIfPresent(Int.self, forKey: .requestTimeout) ?? 60
        gridColumns = try c.decodeIfPresent(Int.self, forKey: .gridColumns) ?? 2
        popoverSizePreset = try c.decodeIfPresent(String.self, forKey: .popoverSizePreset) ?? "standard"
        animatedBackground = try c.decodeIfPresent(Bool.self, forKey: .animatedBackground) ?? true
        autoSelectAllIfEmpty = try c.decodeIfPresent(Bool.self, forKey: .autoSelectAllIfEmpty) ?? true
        maskEndpointKeys = try c.decodeIfPresent(Bool.self, forKey: .maskEndpointKeys) ?? false
        recentCustomPrompts = try c.decodeIfPresent([String].self, forKey: .recentCustomPrompts) ?? []
    }
}

public struct RuntimeConfig: Codable, Equatable {
    public let model: String?
    public let activated_endpoint_id: UUID
    public let model_list: [EndpointItem]
    public let presets: [WritingPresetItem]
    public let settings: RuntimeSettings

    enum CodingKeys: String, CodingKey {
        case model, activated_endpoint_id, model_list, presets, settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        activated_endpoint_id = try c.decodeIfPresent(UUID.self, forKey: .activated_endpoint_id) ?? UUID()
        model_list = try c.decodeIfPresent([EndpointItem].self, forKey: .model_list) ?? []
        presets = try c.decodeIfPresent([WritingPresetItem].self, forKey: .presets) ?? WritingPresetItem.defaultPresets
        settings = try c.decodeIfPresent(RuntimeSettings.self, forKey: .settings) ?? .default
    }
}

public class Configurator: ObservableObject {
    public static let shared = Configurator()

    private let cachedConfigDefaultsKey = "WriteNowCachedRuntimeConfigV1"

    @Published public var endpoints: [EndpointItem] = []
    @Published public var activatedEndpointID: UUID = UUID()
    @Published public var presets: [WritingPresetItem] = WritingPresetItem.defaultPresets
    @Published public var settings: RuntimeSettings = .default
    @Published public var daemonConnected: Bool = true

    public var activeEndpoint: EndpointItem? {
        endpoints.first { $0.id == activatedEndpointID }
    }

    public let openAI: OpenAI = .init(configuration: .init(
        token: "user_activated_token",
        host: "127.0.0.1",
        port: 5540,
        scheme: "http",
        timeoutInterval: 180
    ))

    public let mid: String = "user_activated_model"

    public let gateErrorCheckRequest: URLRequest = {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:5540/metrics?query=status")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        return request
    }()

    public let gateConfigCheckRequest: URLRequest = {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:5540/metrics?query=config")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        return request
    }()

    private init() {
        if let data = UserDefaults.standard.data(forKey: cachedConfigDefaultsKey),
           let cached = try? JSONDecoder().decode(RuntimeConfig.self, from: data)
        {
            applyRuntimeConfig(cached, cacheToDefaults: false)
        }
    }

    public func refreshRuntimeConfig(completion: ((RuntimeConfig?) -> Void)? = nil) {
        URLSession.shared.dataTask(with: gateConfigCheckRequest) { [weak self] data, _, error in
            guard let self else { return }
            guard error == nil, let data,
                  let decoded = try? JSONDecoder().decode(RuntimeConfig.self, from: data)
            else {
                DispatchQueue.main.async {
                    self.daemonConnected = false
                    completion?(nil)
                }
                return
            }
            DispatchQueue.main.async {
                self.daemonConnected = true
                self.applyRuntimeConfig(decoded, cacheToDefaults: true)
                completion?(decoded)
            }
        }.resume()
    }

    private func applyRuntimeConfig(_ cfg: RuntimeConfig, cacheToDefaults: Bool) {
        endpoints = cfg.model_list
        activatedEndpointID = cfg.activated_endpoint_id
        presets = cfg.presets
        settings = cfg.settings
        WritingToolsLocalizable.shared.customMenuTitle = cfg.settings.menuTitle

        if cacheToDefaults, let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: cachedConfigDefaultsKey)
        }
    }

    public func switchEndpoint(id: UUID, completion: ((Bool) -> Void)? = nil) {
        guard let url = URL(string: "http://127.0.0.1:5540/action?command=switch_endpoint&id=\(id.uuidString)") else {
            completion?(false)
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = "GET"
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            let ok = error == nil && ((response as? HTTPURLResponse)?.statusCode == 200)
            if ok {
                self?.refreshRuntimeConfig { _ in
                    completion?(true)
                }
            } else {
                DispatchQueue.main.async { completion?(false) }
            }
        }.resume()
    }

    public func upsertEndpoint(
        id: UUID? = nil,
        name: String,
        url: String,
        token: String,
        model: String,
        pathMode: EndpointItem.PathMode = .auto,
        customHeaders: [String: String] = [:],
        useStreaming: Bool = true,
        timeoutSeconds: Int = 60,
        activate: Bool = true,
        completion: @escaping (Result<RuntimeConfig, Error>) -> Void
    ) {
        var body: [String: Any] = [
            "name": name,
            "url": url,
            "token": token,
            "model": model,
            "pathMode": pathMode.rawValue,
            "customHeaders": customHeaders,
            "useStreaming": useStreaming,
            "timeoutSeconds": timeoutSeconds,
            "activate": activate,
        ]
        if let id { body["id"] = id.uuidString }
        performJSONAction(command: "upsert_endpoint", body: body) { result in
            switch result {
            case let .success(data):
                if let cfg = try? JSONDecoder().decode(RuntimeConfig.self, from: data) {
                    DispatchQueue.main.async {
                        self.daemonConnected = true
                        self.applyRuntimeConfig(cfg, cacheToDefaults: true)
                        completion(.success(cfg))
                    }
                } else {
                    let msg = Self.extractErrorString(from: data) ?? "Invalid daemon response"
                    DispatchQueue.main.async { completion(.failure(NSError(domain: "WriteNow", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))) }
                }
            case let .failure(err):
                DispatchQueue.main.async { completion(.failure(err)) }
            }
        }
    }

    public func deleteEndpoint(id: UUID, completion: ((Bool) -> Void)? = nil) {
        performJSONAction(command: "delete_endpoint", body: ["id": id.uuidString]) { result in
            switch result {
            case let .success(data):
                if let cfg = try? JSONDecoder().decode(RuntimeConfig.self, from: data) {
                    DispatchQueue.main.async {
                        self.applyRuntimeConfig(cfg, cacheToDefaults: true)
                        completion?(true)
                    }
                } else {
                    DispatchQueue.main.async { completion?(false) }
                }
            case .failure:
                DispatchQueue.main.async { completion?(false) }
            }
        }
    }

    public func fetchModelsViaDaemon(
        url: String,
        token: String,
        pathMode: EndpointItem.PathMode = .auto,
        customHeaders: [String: String] = [:],
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        let body: [String: Any] = [
            "url": url,
            "token": token,
            "pathMode": pathMode.rawValue,
            "customHeaders": customHeaders,
        ]
        performJSONAction(command: "fetch_models", body: body, timeout: 25) { result in
            switch result {
            case let .success(data):
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let models = obj["models"] as? [String], !models.isEmpty {
                        DispatchQueue.main.async { completion(.success(models)) }
                        return
                    }
                    let errMsg = (obj["error"] as? String) ?? "No models found"
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "WriteNow", code: -1, userInfo: [NSLocalizedDescriptionKey: errMsg])))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "WriteNow", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                    }
                }
            case let .failure(err):
                DispatchQueue.main.async { completion(.failure(err)) }
            }
        }
    }

    public func testEndpointViaDaemon(
        url: String,
        token: String,
        model: String,
        pathMode: EndpointItem.PathMode = .auto,
        customHeaders: [String: String] = [:],
        timeoutSeconds: Int = 30,
        completion: @escaping (Bool, String) -> Void
    ) {
        let body: [String: Any] = [
            "url": url,
            "token": token,
            "model": model,
            "pathMode": pathMode.rawValue,
            "customHeaders": customHeaders,
            "timeoutSeconds": timeoutSeconds,
        ]
        performJSONAction(command: "test_endpoint", body: body, timeout: TimeInterval(max(15, timeoutSeconds + 5))) { result in
            switch result {
            case let .success(data):
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let ok = (obj["ok"] as? Bool) ?? false
                    let msg = (obj["message"] as? String) ?? (ok ? "OK" : "Failed")
                    DispatchQueue.main.async { completion(ok, msg) }
                } else {
                    DispatchQueue.main.async { completion(false, "Invalid response") }
                }
            case let .failure(err):
                DispatchQueue.main.async { completion(false, err.localizedDescription) }
            }
        }
    }

    public func recordQuickPrompt(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DispatchQueue.main.async {
            var recent = self.settings.recentCustomPrompts.filter { $0 != trimmed }
            recent.insert(trimmed, at: 0)
            if recent.count > 8 { recent = Array(recent.prefix(8)) }
            self.settings.recentCustomPrompts = recent
        }
        performJSONAction(command: "record_quick_prompt", body: ["prompt": trimmed]) { _ in }
    }

    private func performJSONAction(
        command: String,
        body: [String: Any],
        timeout: TimeInterval = 10,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard let url = URL(string: "http://127.0.0.1:5540/action?command=\(command)"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body)
        else {
            completion(.failure(NSError(domain: "WriteNow", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid request"])))
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data else {
                completion(.failure(NSError(domain: "WriteNow", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty response"])))
                return
            }
            completion(.success(data))
        }.resume()
    }

    private static func extractErrorString(from data: Data) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? String
        {
            return err
        }
        return nil
    }
}

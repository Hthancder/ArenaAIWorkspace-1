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
    public var models: [String]
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

    public var effectiveModels: [String] {
        Self.normalizeModels(models, active: model)
    }

    public static func normalizeModels(_ list: [String], active: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in list {
            let t = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, seen.insert(t).inserted {
                result.append(t)
            }
        }
        let activeTrimmed = active.trimmingCharacters(in: .whitespacesAndNewlines)
        if !activeTrimmed.isEmpty, seen.insert(activeTrimmed).inserted {
            result.insert(activeTrimmed, at: 0)
        }
        return result
    }

    public init(
        id: UUID = UUID(),
        create: Date = Date(),
        name: String = "",
        url: URL,
        token: String = "",
        model: String = "",
        models: [String] = [],
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
        let trimmedActive = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedList = Self.normalizeModels(models, active: trimmedActive)
        self.models = normalizedList
        self.model = trimmedActive.isEmpty ? (normalizedList.first ?? "") : trimmedActive
        self.pathMode = pathMode
        self.customHeaders = customHeaders
        self.useStreaming = useStreaming
        self.timeoutSeconds = timeoutSeconds
    }

    enum CodingKeys: String, CodingKey {
        case id, create, name, url, token, model, models, pathMode, customHeaders, useStreaming, timeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        create = try c.decodeIfPresent(Date.self, forKey: .create) ?? Date()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try c.decode(URL.self, forKey: .url)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        let decodedModel = (try c.decodeIfPresent(String.self, forKey: .model) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decodedModels = try c.decodeIfPresent([String].self, forKey: .models) ?? []
        let normalizedList = Self.normalizeModels(decodedModels, active: decodedModel)
        models = normalizedList
        model = decodedModel.isEmpty ? (normalizedList.first ?? "") : decodedModel
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
    public var accentColorHex: String
    public var menuThemePreset: String
    public var backgroundMode: String
    public var customThemeColorsHex: [String]
    public var solidBackgroundHex: String
    public var backgroundImageBlur: Double
    public var backgroundImageDim: Double
    public var backgroundImageRevision: String
    public var textReplacementAnimation: String
    public var stt: RuntimeSTTSettings

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
        recentCustomPrompts: [],
        accentColorHex: "#3B82F6",
        menuThemePreset: "midnight_ocean",
        backgroundMode: "mesh",
        customThemeColorsHex: ["#3B82F6", "#8B5CF6", "#06B6D4", "#0F172A"],
        solidBackgroundHex: "#111827",
        backgroundImageBlur: 6.0,
        backgroundImageDim: 0.45,
        backgroundImageRevision: "",
        textReplacementAnimation: "scatter_assemble",
        stt: .default
    )

    enum CodingKeys: String, CodingKey {
        case menuTitle, globalSystemPrompt, useFewShotExamples, stripThinkingTags
        case streamingEnabled, requestTimeout, gridColumns, popoverSizePreset
        case animatedBackground, autoSelectAllIfEmpty, maskEndpointKeys, recentCustomPrompts
        case accentColorHex, menuThemePreset, backgroundMode, customThemeColorsHex
        case solidBackgroundHex, backgroundImageBlur, backgroundImageDim
        case backgroundImageRevision, textReplacementAnimation, stt
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
        recentCustomPrompts: [String] = [],
        accentColorHex: String = "#3B82F6",
        menuThemePreset: String = "midnight_ocean",
        backgroundMode: String = "mesh",
        customThemeColorsHex: [String] = ["#3B82F6", "#8B5CF6", "#06B6D4", "#0F172A"],
        solidBackgroundHex: String = "#111827",
        backgroundImageBlur: Double = 6.0,
        backgroundImageDim: Double = 0.45,
        backgroundImageRevision: String = "",
        textReplacementAnimation: String = "scatter_assemble",
        stt: RuntimeSTTSettings = .default
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
        self.accentColorHex = accentColorHex
        self.menuThemePreset = menuThemePreset
        self.backgroundMode = backgroundMode
        self.customThemeColorsHex = customThemeColorsHex
        self.solidBackgroundHex = solidBackgroundHex
        self.backgroundImageBlur = backgroundImageBlur
        self.backgroundImageDim = backgroundImageDim
        self.backgroundImageRevision = backgroundImageRevision
        self.textReplacementAnimation = textReplacementAnimation
        self.stt = stt
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
        accentColorHex = try c.decodeIfPresent(String.self, forKey: .accentColorHex) ?? "#3B82F6"
        menuThemePreset = try c.decodeIfPresent(String.self, forKey: .menuThemePreset) ?? "midnight_ocean"
        backgroundMode = try c.decodeIfPresent(String.self, forKey: .backgroundMode) ?? (animatedBackground ? "mesh" : "gradient")
        customThemeColorsHex = try c.decodeIfPresent([String].self, forKey: .customThemeColorsHex) ?? ["#3B82F6", "#8B5CF6", "#06B6D4", "#0F172A"]
        solidBackgroundHex = try c.decodeIfPresent(String.self, forKey: .solidBackgroundHex) ?? "#111827"
        backgroundImageBlur = try c.decodeIfPresent(Double.self, forKey: .backgroundImageBlur) ?? 6.0
        backgroundImageDim = try c.decodeIfPresent(Double.self, forKey: .backgroundImageDim) ?? 0.45
        backgroundImageRevision = try c.decodeIfPresent(String.self, forKey: .backgroundImageRevision) ?? ""
        textReplacementAnimation = try c.decodeIfPresent(String.self, forKey: .textReplacementAnimation) ?? "scatter_assemble"
        stt = try c.decodeIfPresent(RuntimeSTTSettings.self, forKey: .stt) ?? .default
    }
}

public struct RuntimeSTTSettings: Codable, Equatable {
    public var enabled: Bool
    public var providerType: String
    public var presetKind: String
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var pathMode: EndpointItem.PathMode
    public var customHeaders: [String: String]
    public var timeoutSeconds: Int
    public var sourceLanguage: String
    public var targetLanguage: String
    public var voiceMode: String
    public var translationStrategy: String
    public var translationStyle: String
    public var promptHint: String
    public var temperature: Double
    public var audioFormat: String
    public var maxDurationSeconds: Int
    public var autoSendVoicePrompt: Bool
    public var appleOnDeviceOnly: Bool

    public static let `default` = RuntimeSTTSettings(
        enabled: true,
        providerType: "openai_compatible",
        presetKind: "groq",
        baseURL: "https://api.groq.com/openai",
        apiKey: "",
        model: "whisper-large-v3-turbo",
        pathMode: .auto,
        customHeaders: [:],
        timeoutSeconds: 35,
        sourceLanguage: "auto",
        targetLanguage: "vi",
        voiceMode: "prompt",
        translationStrategy: "hybrid",
        translationStyle: "natural",
        promptHint: "",
        temperature: 0.0,
        audioFormat: "m4a",
        maxDurationSeconds: 60,
        autoSendVoicePrompt: true,
        appleOnDeviceOnly: false
    )

    public init(
        enabled: Bool = true,
        providerType: String = "openai_compatible",
        presetKind: String = "groq",
        baseURL: String = "https://api.groq.com/openai",
        apiKey: String = "",
        model: String = "whisper-large-v3-turbo",
        pathMode: EndpointItem.PathMode = .auto,
        customHeaders: [String: String] = [:],
        timeoutSeconds: Int = 35,
        sourceLanguage: String = "auto",
        targetLanguage: String = "vi",
        voiceMode: String = "prompt",
        translationStrategy: String = "hybrid",
        translationStyle: String = "natural",
        promptHint: String = "",
        temperature: Double = 0.0,
        audioFormat: String = "m4a",
        maxDurationSeconds: Int = 60,
        autoSendVoicePrompt: Bool = true,
        appleOnDeviceOnly: Bool = false
    ) {
        self.enabled = enabled
        self.providerType = providerType
        self.presetKind = presetKind
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.pathMode = pathMode
        self.customHeaders = customHeaders
        self.timeoutSeconds = timeoutSeconds
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.voiceMode = voiceMode
        self.translationStrategy = translationStrategy
        self.translationStyle = translationStyle
        self.promptHint = promptHint
        self.temperature = temperature
        self.audioFormat = audioFormat
        self.maxDurationSeconds = maxDurationSeconds
        self.autoSendVoicePrompt = autoSendVoicePrompt
        self.appleOnDeviceOnly = appleOnDeviceOnly
    }

    enum CodingKeys: String, CodingKey {
        case enabled, providerType, presetKind, baseURL, apiKey, model, pathMode
        case customHeaders, timeoutSeconds, sourceLanguage, targetLanguage, voiceMode
        case translationStrategy, translationStyle, promptHint, temperature
        case audioFormat, maxDurationSeconds, autoSendVoicePrompt, appleOnDeviceOnly
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        providerType = try c.decodeIfPresent(String.self, forKey: .providerType) ?? "openai_compatible"
        presetKind = try c.decodeIfPresent(String.self, forKey: .presetKind) ?? "groq"
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://api.groq.com/openai"
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "whisper-large-v3-turbo"
        pathMode = try c.decodeIfPresent(EndpointItem.PathMode.self, forKey: .pathMode) ?? .auto
        customHeaders = try c.decodeIfPresent([String: String].self, forKey: .customHeaders) ?? [:]
        timeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 35
        sourceLanguage = try c.decodeIfPresent(String.self, forKey: .sourceLanguage) ?? "auto"
        targetLanguage = try c.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "vi"
        voiceMode = try c.decodeIfPresent(String.self, forKey: .voiceMode) ?? "prompt"
        translationStrategy = try c.decodeIfPresent(String.self, forKey: .translationStrategy) ?? "hybrid"
        translationStyle = try c.decodeIfPresent(String.self, forKey: .translationStyle) ?? "natural"
        promptHint = try c.decodeIfPresent(String.self, forKey: .promptHint) ?? ""
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.0
        audioFormat = try c.decodeIfPresent(String.self, forKey: .audioFormat) ?? "m4a"
        maxDurationSeconds = try c.decodeIfPresent(Int.self, forKey: .maxDurationSeconds) ?? 60
        autoSendVoicePrompt = try c.decodeIfPresent(Bool.self, forKey: .autoSendVoicePrompt) ?? true
        appleOnDeviceOnly = try c.decodeIfPresent(Bool.self, forKey: .appleOnDeviceOnly) ?? false
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
    private let cachedBgImageKey = "WriteNowCachedBgImageDataV1"
    private let cachedBgRevKey = "WriteNowCachedBgImageRevV1"

    @Published public var endpoints: [EndpointItem] = []
    @Published public var activatedEndpointID: UUID = UUID()
    @Published public var presets: [WritingPresetItem] = WritingPresetItem.defaultPresets
    @Published public var settings: RuntimeSettings = .default
    @Published public var daemonConnected: Bool = true
    @Published public var customBackgroundImageData: Data? = nil

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
        customBackgroundImageData = UserDefaults.standard.data(forKey: cachedBgImageKey)
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
                self.refreshBackgroundImageIfNeeded(revision: decoded.settings.backgroundImageRevision, mode: decoded.settings.backgroundMode)
                completion?(decoded)
            }
        }.resume()
    }

    private func refreshBackgroundImageIfNeeded(revision: String, mode: String) {
        if revision.isEmpty {
            if customBackgroundImageData != nil {
                customBackgroundImageData = nil
                UserDefaults.standard.removeObject(forKey: cachedBgImageKey)
                UserDefaults.standard.removeObject(forKey: cachedBgRevKey)
            }
            return
        }
        guard mode == "image" else { return }
        let cachedRev = UserDefaults.standard.string(forKey: cachedBgRevKey) ?? ""
        if cachedRev == revision, customBackgroundImageData != nil {
            return
        }
        guard let url = URL(string: "http://127.0.0.1:5540/metrics?query=bg_image") else { return }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 5)
        req.httpMethod = "GET"
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self, error == nil, let data, !data.isEmpty else { return }
            DispatchQueue.main.async {
                self.customBackgroundImageData = data
                UserDefaults.standard.set(data, forKey: self.cachedBgImageKey)
                UserDefaults.standard.set(revision, forKey: self.cachedBgRevKey)
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

    public func switchEndpoint(id: UUID, model: String? = nil, completion: ((Bool) -> Void)? = nil) {
        var comps = URLComponents(string: "http://127.0.0.1:5540/action")!
        var items = [
            URLQueryItem(name: "command", value: "switch_endpoint"),
            URLQueryItem(name: "id", value: id.uuidString),
        ]
        if let model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "model", value: model.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        comps.queryItems = items
        guard let url = comps.url else {
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
        models: [String] = [],
        pathMode: EndpointItem.PathMode = .auto,
        customHeaders: [String: String] = [:],
        useStreaming: Bool = true,
        timeoutSeconds: Int = 60,
        activate: Bool = true,
        completion: @escaping (Result<RuntimeConfig, Error>) -> Void
    ) {
        let normalizedModels = EndpointItem.normalizeModels(models, active: model)
        var body: [String: Any] = [
            "name": name,
            "url": url,
            "token": token,
            "model": model,
            "models": normalizedModels,
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

    // MARK: - Voice / STT IPC

    public func startVoiceRecording(completion: @escaping (Bool, String?) -> Void) {
        performJSONAction(command: "stt_start", body: [:], timeout: 8) { result in
            switch result {
            case let .success(data):
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let ok = (obj["ok"] as? Bool) ?? true
                    let err = obj["error"] as? String
                    DispatchQueue.main.async { completion(ok, err) }
                } else {
                    DispatchQueue.main.async { completion(false, "Invalid daemon response") }
                }
            case let .failure(err):
                DispatchQueue.main.async { completion(false, err.localizedDescription) }
            }
        }
    }

    public func cancelVoiceRecording() {
        performJSONAction(command: "stt_cancel", body: [:], timeout: 5) { _ in }
    }

    public func fetchSTTStatus(completion: @escaping (_ recording: Bool, _ duration: Double, _ level: Double, _ maxDuration: Double) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:5540/metrics?query=stt_status") else {
            DispatchQueue.main.async { completion(false, 0, 0, 60) }
            return
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 2)
        req.httpMethod = "GET"
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                DispatchQueue.main.async { completion(false, 0, 0, 60) }
                return
            }
            let rec = (obj["recording"] as? Bool) ?? false
            let dur = (obj["duration"] as? Double) ?? 0
            let lvl = (obj["level"] as? Double) ?? 0
            let maxD = (obj["maxDuration"] as? Double) ?? 60
            DispatchQueue.main.async { completion(rec, dur, lvl, maxD) }
        }.resume()
    }

    public func stopVoiceRecording(
        mode: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (_ ok: Bool, _ transcript: String, _ finalText: String, _ provider: String, _ warning: String?, _ errorMessage: String?) -> Void
    ) {
        let body: [String: Any] = [
            "mode": mode,
            "sourceLanguage": sourceLanguage,
            "targetLanguage": targetLanguage,
        ]
        performJSONAction(command: "stt_stop", body: body, timeout: 65) { result in
            switch result {
            case let .success(data):
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let ok = (obj["ok"] as? Bool) ?? false
                    let transcript = (obj["transcript"] as? String) ?? ""
                    let finalText = (obj["finalText"] as? String) ?? transcript
                    let provider = (obj["providerUsed"] as? String) ?? ""
                    let warning = obj["warning"] as? String
                    let err = obj["error"] as? String
                    DispatchQueue.main.async {
                        completion(ok, transcript, finalText, provider, warning, err)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(false, "", "", "", nil, "Invalid STT response")
                    }
                }
            case let .failure(err):
                DispatchQueue.main.async {
                    completion(false, "", "", "", nil, err.localizedDescription)
                }
            }
        }
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

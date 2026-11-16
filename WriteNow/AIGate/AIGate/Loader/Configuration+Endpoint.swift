//
//  Configuration+Endpoint.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/25.
//

import Foundation

extension Configuration {
    struct Endpoint: Codable, Identifiable, Equatable, Hashable {
        enum PathMode: String, Codable, CaseIterable, Hashable {
            case auto
            case raw

            var displayName: String {
                switch self {
                case .auto: return "Auto (/v1 smart)"
                case .raw: return "Raw (as entered)"
                }
            }
        }

        let id: UUID
        let create: Date

        var name: String
        var url: URL
        var token: String
        var model: String
        var pathMode: PathMode
        var customHeaders: [String: String]
        var useStreaming: Bool
        var timeoutSeconds: Int

        var displayName: String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            if let host = url.host, !host.isEmpty {
                if let port = url.port {
                    return "\(host):\(port)"
                }
                return host
            }
            return url.absoluteString
        }

        var displayModel: String {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "(No Model ID)" : trimmed
        }

        init(
            id: UUID = .init(),
            create: Date = Date(),
            name: String = "",
            url: URL,
            token: String,
            model: String,
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

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            create = try container.decodeIfPresent(Date.self, forKey: .create) ?? Date()
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            url = try container.decode(URL.self, forKey: .url)
            token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
            model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
            pathMode = try container.decodeIfPresent(PathMode.self, forKey: .pathMode) ?? .auto
            customHeaders = try container.decodeIfPresent([String: String].self, forKey: .customHeaders) ?? [:]
            useStreaming = try container.decodeIfPresent(Bool.self, forKey: .useStreaming) ?? true
            timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 60
        }
    }

    struct WritingPreset: Codable, Identifiable, Equatable, Hashable {
        enum InsertBehavior: String, Codable, CaseIterable, Hashable {
            case replace
            case append
        }

        let id: UUID
        var defaultKey: String?
        var title: String
        var icon: String
        var systemPrompt: String
        var temperature: Double
        var topP: Double?
        var includeExamples: Bool
        var outputLanguage: String
        var insertBehavior: InsertBehavior
        var isEnabled: Bool

        init(
            id: UUID = .init(),
            defaultKey: String? = nil,
            title: String,
            icon: String,
            systemPrompt: String,
            temperature: Double = 0.3,
            topP: Double? = nil,
            includeExamples: Bool = false,
            outputLanguage: String = "",
            insertBehavior: InsertBehavior = .replace,
            isEnabled: Bool = true
        ) {
            self.id = id
            self.defaultKey = defaultKey
            self.title = title
            self.icon = icon
            self.systemPrompt = systemPrompt
            self.temperature = temperature
            self.topP = topP
            self.includeExamples = includeExamples
            self.outputLanguage = outputLanguage
            self.insertBehavior = insertBehavior
            self.isEnabled = isEnabled
        }

        enum CodingKeys: String, CodingKey {
            case id, defaultKey, title, icon, systemPrompt, temperature, topP, includeExamples, outputLanguage, insertBehavior, isEnabled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            defaultKey = try container.decodeIfPresent(String.self, forKey: .defaultKey)
            title = try container.decode(String.self, forKey: .title)
            icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "sparkles"
            systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
            temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.3
            topP = try container.decodeIfPresent(Double.self, forKey: .topP)
            includeExamples = try container.decodeIfPresent(Bool.self, forKey: .includeExamples) ?? false
            outputLanguage = try container.decodeIfPresent(String.self, forKey: .outputLanguage) ?? ""
            insertBehavior = try container.decodeIfPresent(InsertBehavior.self, forKey: .insertBehavior) ?? .replace
            isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        }

        static let defaultPresets: [WritingPreset] = [
            WritingPreset(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111101")!,
                defaultKey: "proofread",
                title: "Proofread",
                icon: "doc.text.magnifyingglass",
                systemPrompt: "Proofread the text: correct spelling, grammar, punctuation, and minor word choices while keeping meaning and tone. Make the smallest necessary edits; if the text is already correct, leave it unchanged. Do not rephrase extensively or add content.",
                temperature: 0.15,
                topP: nil,
                includeExamples: true,
                outputLanguage: "",
                insertBehavior: .replace,
                isEnabled: true
            ),
            WritingPreset(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111102")!,
                defaultKey: "rewrite",
                title: "Rewrite",
                icon: "arrow.counterclockwise",
                systemPrompt: "Rewrite the text for clarity and flow while preserving all original meaning. You may reorganize sentences and refine wording to improve readability, but do not introduce new facts or omit essential details. If the original is strong, keep changes subtle.",
                temperature: 0.35,
                topP: nil,
                includeExamples: true,
                outputLanguage: "",
                insertBehavior: .replace,
                isEnabled: true
            ),
            WritingPreset(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111103")!,
                defaultKey: "friendly",
                title: "Friendly",
                icon: "bubble.left.and.bubble.right",
                systemPrompt: "Rewrite the text to sound approachable and warm while staying faithful to the original. Keep it clear, engaging, and concise; avoid slang unless present in the source. Warmth is mild—do not overdo enthusiasm.",
                temperature: 0.55,
                topP: 0.9,
                includeExamples: true,
                outputLanguage: "",
                insertBehavior: .replace,
                isEnabled: true
            ),
            WritingPreset(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111104")!,
                defaultKey: "professional",
                title: "Professional",
                icon: "books.vertical",
                systemPrompt: "Rewrite the text in a clear, concise, and formal style suitable for professional or business contexts. Preserve all facts and intent; emphasize precision and readability without adding commentary.",
                temperature: 0.2,
                topP: nil,
                includeExamples: true,
                outputLanguage: "",
                insertBehavior: .replace,
                isEnabled: true
            ),
            WritingPreset(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111105")!,
                defaultKey: "concise",
                title: "Concise",
                icon: "textformat.abc.dottedunderline",
                systemPrompt: "Make the text concise: keep essential information and intent, remove redundancy, and tighten phrasing. Ensure the result remains clear and faithful to the original.",
                temperature: 0.2,
                topP: nil,
                includeExamples: true,
                outputLanguage: "",
                insertBehavior: .replace,
                isEnabled: true
            ),
        ]
    }

    struct AppSettings: Codable, Equatable {
        var menuTitle: String
        var globalSystemPrompt: String
        var useFewShotExamples: Bool
        var stripThinkingTags: Bool
        var streamingEnabled: Bool
        var requestTimeout: Int
        var gridColumns: Int
        var popoverSizePreset: String
        var animatedBackground: Bool
        var autoSelectAllIfEmpty: Bool
        var maskEndpointKeys: Bool
        var recentCustomPrompts: [String]

        static let `default` = AppSettings(
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

        init(
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

        enum CodingKeys: String, CodingKey {
            case menuTitle, globalSystemPrompt, useFewShotExamples, stripThinkingTags
            case streamingEnabled, requestTimeout, gridColumns, popoverSizePreset
            case animatedBackground, autoSelectAllIfEmpty, maskEndpointKeys, recentCustomPrompts
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            menuTitle = try container.decodeIfPresent(String.self, forKey: .menuTitle) ?? "Write Now"
            globalSystemPrompt = try container.decodeIfPresent(String.self, forKey: .globalSystemPrompt) ?? ""
            useFewShotExamples = try container.decodeIfPresent(Bool.self, forKey: .useFewShotExamples) ?? true
            stripThinkingTags = try container.decodeIfPresent(Bool.self, forKey: .stripThinkingTags) ?? true
            streamingEnabled = try container.decodeIfPresent(Bool.self, forKey: .streamingEnabled) ?? true
            requestTimeout = try container.decodeIfPresent(Int.self, forKey: .requestTimeout) ?? 60
            gridColumns = try container.decodeIfPresent(Int.self, forKey: .gridColumns) ?? 2
            popoverSizePreset = try container.decodeIfPresent(String.self, forKey: .popoverSizePreset) ?? "standard"
            animatedBackground = try container.decodeIfPresent(Bool.self, forKey: .animatedBackground) ?? true
            autoSelectAllIfEmpty = try container.decodeIfPresent(Bool.self, forKey: .autoSelectAllIfEmpty) ?? true
            maskEndpointKeys = try container.decodeIfPresent(Bool.self, forKey: .maskEndpointKeys) ?? false
            recentCustomPrompts = try container.decodeIfPresent([String].self, forKey: .recentCustomPrompts) ?? []
        }
    }

    struct BackupPayload: Codable {
        var version: Int = 1
        var endpoints: [Endpoint]
        var activatedEndpointID: UUID
        var presets: [WritingPreset]
        var settings: AppSettings
    }

    struct RuntimeConfigPayload: Codable {
        let model: String?
        let activated_endpoint_id: UUID
        let model_list: [Endpoint]
        let presets: [WritingPreset]
        let settings: AppSettings
    }
}

enum EndpointURLHelper {
    static func normalizeBaseURL(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !trimmed.contains("://") {
            let lower = trimmed.lowercased()
            let isLocal = lower.hasPrefix("localhost")
                || lower.hasPrefix("127.0.0.1")
                || lower.hasPrefix("10.")
                || lower.hasPrefix("192.168.")
                || lower.hasPrefix("172.")
            trimmed = (isLocal ? "http://" : "https://") + trimmed
        }

        guard var components = URLComponents(string: trimmed),
              let host = components.host, !host.isEmpty
        else {
            return nil
        }

        var path = components.path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }

        for suffix in ["/chat/completions", "/completions", "/models"] {
            if path.lowercased().hasSuffix(suffix) {
                path = String(path.dropLast(suffix.count))
                while path.count > 1, path.hasSuffix("/") {
                    path.removeLast()
                }
                break
            }
        }

        components.path = path == "/" ? "" : path
        return components.url
    }

    private static func hasExplicitAPIVersionSuffix(_ path: String, host: String?) -> Bool {
        if host?.lowercased() == "models.inference.ai.azure.com" {
            return true
        }
        let lower = path.lowercased()
        if lower.hasSuffix("/v1beta/openai") || lower.hasSuffix("/v1alpha/openai") || lower.hasSuffix("/openai/v1") {
            return true
        }
        if let range = lower.range(of: #"/v\d+([a-z0-9]*)?$"#, options: .regularExpression) {
            return !range.isEmpty
        }
        return false
    }

    static func buildUpstreamURI(baseURL: URL, requestURI: String, pathMode: Configuration.Endpoint.PathMode) -> String {
        let uriParts = requestURI.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let reqPath = String(uriParts.first ?? "/")
        let reqQuery = uriParts.count > 1 ? String(uriParts[1]) : nil

        let suffix: String
        if reqPath == "/v1" {
            suffix = ""
        } else if reqPath.hasPrefix("/v1/") {
            suffix = String(reqPath.dropFirst(3)) // includes leading "/"
        } else {
            suffix = reqPath
        }

        var basePath = baseURL.path
        while basePath.hasSuffix("/") {
            basePath.removeLast()
        }

        let finalPath: String
        switch pathMode {
        case .raw:
            if basePath.lowercased().hasSuffix("/chat/completions"), suffix == "/chat/completions" {
                finalPath = basePath
            } else if basePath.isEmpty {
                finalPath = reqPath
            } else {
                finalPath = basePath + (suffix.isEmpty ? reqPath : suffix)
            }
        case .auto:
            if hasExplicitAPIVersionSuffix(basePath, host: baseURL.host) {
                finalPath = basePath + (suffix.isEmpty ? "" : suffix)
            } else if basePath.isEmpty {
                finalPath = "/v1" + (suffix.isEmpty ? "" : suffix)
            } else {
                finalPath = basePath + "/v1" + (suffix.isEmpty ? "" : suffix)
            }
        }

        let baseQuery = baseURL.query
        let combinedQuery: String?
        switch (baseQuery, reqQuery) {
        case let (.some(bq), .some(rq)) where !bq.isEmpty && !rq.isEmpty:
            combinedQuery = "\(bq)&\(rq)"
        case let (.some(bq), _) where !bq.isEmpty:
            combinedQuery = bq
        case let (_, .some(rq)) where !rq.isEmpty:
            combinedQuery = rq
        default:
            combinedQuery = nil
        }

        if let combinedQuery {
            return "\(finalPath)?\(combinedQuery)"
        }
        return finalPath.isEmpty ? "/" : finalPath
    }

    static func candidateModelsURLs(baseURL: URL, pathMode: Configuration.Endpoint.PathMode) -> [URL] {
        var urls: [URL] = []
        let primaryURI = buildUpstreamURI(baseURL: baseURL, requestURI: "/v1/models", pathMode: pathMode)
        if let primary = makeURL(baseURL: baseURL, uri: primaryURI) {
            urls.append(primary)
        }
        let v1Fallback = buildUpstreamURI(baseURL: baseURL, requestURI: "/v1/models", pathMode: .auto)
        if let u = makeURL(baseURL: baseURL, uri: v1Fallback), !urls.contains(u) {
            urls.append(u)
        }
        var basePath = baseURL.path
        while basePath.hasSuffix("/") { basePath.removeLast() }
        if let bare = makeURL(baseURL: baseURL, uri: "\(basePath)/models"), !urls.contains(bare) {
            urls.append(bare)
        }
        return urls
    }

    static func chatCompletionsURL(baseURL: URL, pathMode: Configuration.Endpoint.PathMode) -> URL? {
        let uri = buildUpstreamURI(baseURL: baseURL, requestURI: "/v1/chat/completions", pathMode: pathMode)
        return makeURL(baseURL: baseURL, uri: uri)
    }

    private static func makeURL(baseURL: URL, uri: String) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let parts = uri.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        components?.path = String(parts.first ?? "/")
        components?.percentEncodedQuery = parts.count > 1 ? String(parts[1]) : nil
        return components?.url
    }
}

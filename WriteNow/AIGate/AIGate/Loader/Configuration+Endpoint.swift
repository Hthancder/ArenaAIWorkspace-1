//
//  Configuration+Endpoint.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/25.
//

import Foundation
import SwiftUI
import UIKit

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
        var models: [String]
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

        var effectiveModels: [String] {
            Self.normalizeModels(models, active: model)
        }

        var providerGroupKey: String {
            let base = EndpointURLHelper.normalizeBaseURL(url.absoluteString)?.absoluteString.lowercased()
                ?? url.absoluteString.lowercased()
            return "\(base)||\(token.trimmingCharacters(in: .whitespacesAndNewlines))"
        }

        static func normalizeModels(_ list: [String], active: String) -> [String] {
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

        init(
            id: UUID = .init(),
            create: Date = Date(),
            name: String = "",
            url: URL,
            token: String,
            model: String,
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

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            create = try container.decodeIfPresent(Date.self, forKey: .create) ?? Date()
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            url = try container.decode(URL.self, forKey: .url)
            token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
            let decodedModel = (try container.decodeIfPresent(String.self, forKey: .model) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let decodedModels = try container.decodeIfPresent([String].self, forKey: .models) ?? []
            let normalizedList = Self.normalizeModels(decodedModels, active: decodedModel)
            models = normalizedList
            model = decodedModel.isEmpty ? (normalizedList.first ?? "") : decodedModel
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

        enum Availability: String, Codable, CaseIterable, Hashable {
            case both
            case editableOnly
            case readOnlyOnly

            var displayName: String {
                switch self {
                case .both: return "Editable & Read-Only"
                case .editableOnly: return "Editable Only"
                case .readOnlyOnly: return "Read-Only Only"
                }
            }

            var shortLabel: String {
                switch self {
                case .both: return "All"
                case .editableOnly: return "Edit"
                case .readOnlyOnly: return "Read"
                }
            }
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
        var endpointID: UUID?
        var modelOverride: String
        var availability: Availability

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
            isEnabled: Bool = true,
            endpointID: UUID? = nil,
            modelOverride: String = "",
            availability: Availability = .both
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
            self.endpointID = endpointID
            self.modelOverride = modelOverride
            self.availability = availability
        }

        enum CodingKeys: String, CodingKey {
            case id, defaultKey, title, icon, systemPrompt, temperature, topP, includeExamples, outputLanguage, insertBehavior, isEnabled, endpointID, modelOverride, availability
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
            endpointID = try container.decodeIfPresent(UUID.self, forKey: .endpointID)
            modelOverride = try container.decodeIfPresent(String.self, forKey: .modelOverride) ?? ""
            if let decodedAvail = try container.decodeIfPresent(Availability.self, forKey: .availability) {
                availability = decodedAvail
            } else {
                switch defaultKey {
                case "proofread", "rewrite", "friendly", "professional", "concise":
                    availability = .editableOnly
                default:
                    availability = .both
                }
            }
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
                isEnabled: true,
                availability: .editableOnly
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
                isEnabled: true,
                availability: .editableOnly
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
                isEnabled: true,
                availability: .editableOnly
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
                isEnabled: true,
                availability: .editableOnly
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
                isEnabled: true,
                availability: .editableOnly
            ),
            WritingPreset(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111106")!,
                defaultKey: "translate",
                title: "Translate",
                icon: "globe",
                systemPrompt: "Translate the text accurately and naturally. If an output language is configured, strictly output in that language; otherwise translate into natural Vietnamese if the source is in another language, or into natural English if the source is already in Vietnamese. Preserve meaning, tone, and structure.",
                temperature: 0.2,
                topP: nil,
                includeExamples: false,
                outputLanguage: "",
                insertBehavior: .replace,
                isEnabled: true,
                availability: .both
            ),
            WritingPreset(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111107")!,
                defaultKey: "summary",
                title: "Summary",
                icon: "text.alignleft",
                systemPrompt: "Summarize the provided text clearly and accurately, capturing the main ideas and essential details without adding commentary.",
                temperature: 0.25,
                topP: nil,
                includeExamples: false,
                outputLanguage: "",
                insertBehavior: .replace,
                isEnabled: true,
                availability: .both
            ),
            WritingPreset(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111108")!,
                defaultKey: "keyPoints",
                title: "Key Points",
                icon: "list.bullet",
                systemPrompt: "Extract the key points from the provided text as clear, concise bullet points in the same language.",
                temperature: 0.25,
                topP: nil,
                includeExamples: false,
                outputLanguage: "",
                insertBehavior: .replace,
                isEnabled: true,
                availability: .both
            ),
            WritingPreset(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111109")!,
                defaultKey: "explain",
                title: "Explain",
                icon: "lightbulb",
                systemPrompt: "Explain the provided text clearly in plain, easy-to-understand language. Clarify unfamiliar terms, context, or implications concisely in the reader's language (or Vietnamese/English as appropriate).",
                temperature: 0.3,
                topP: nil,
                includeExamples: false,
                outputLanguage: "",
                insertBehavior: .replace,
                isEnabled: true,
                availability: .readOnlyOnly
            ),
            WritingPreset(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111110")!,
                defaultKey: "draftReply",
                title: "Draft Reply",
                icon: "arrowshape.turn.up.left",
                systemPrompt: "Draft a clear, natural, ready-to-send reply to the provided message or email in the same language and an appropriate polite tone.",
                temperature: 0.45,
                topP: nil,
                includeExamples: false,
                outputLanguage: "",
                insertBehavior: .replace,
                isEnabled: true,
                availability: .readOnlyOnly
            ),
        ]

        static let readOnlySeedPresets: [WritingPreset] = Array(defaultPresets.suffix(5))
    }

    struct SelectionMenuItem: Codable, Identifiable, Equatable, Hashable {
        enum ActionKind: String, Codable, CaseIterable, Hashable {
            case preset
            case customPrompt
            case smartReply
            case voicePrompt

            var displayName: String {
                switch self {
                case .preset: return "Run Preset"
                case .customPrompt: return "Custom Prompt"
                case .smartReply: return "Smart Reply"
                case .voicePrompt: return "Voice Input"
                }
            }
        }

        let id: UUID
        var title: String
        var icon: String
        var actionKind: ActionKind
        var presetID: UUID?
        var customPrompt: String
        var availability: WritingPreset.Availability
        var isEnabled: Bool

        init(
            id: UUID = UUID(),
            title: String,
            icon: String = "sparkles",
            actionKind: ActionKind = .preset,
            presetID: UUID? = nil,
            customPrompt: String = "",
            availability: WritingPreset.Availability = .both,
            isEnabled: Bool = true
        ) {
            self.id = id
            self.title = title
            self.icon = icon
            self.actionKind = actionKind
            self.presetID = presetID
            self.customPrompt = customPrompt
            self.availability = availability
            self.isEnabled = isEnabled
        }

        enum CodingKeys: String, CodingKey {
            case id, title, icon, actionKind, presetID, customPrompt, availability, isEnabled
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            title = try c.decode(String.self, forKey: .title)
            icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "sparkles"
            actionKind = try c.decodeIfPresent(ActionKind.self, forKey: .actionKind) ?? .preset
            presetID = try c.decodeIfPresent(UUID.self, forKey: .presetID)
            customPrompt = try c.decodeIfPresent(String.self, forKey: .customPrompt) ?? ""
            availability = try c.decodeIfPresent(WritingPreset.Availability.self, forKey: .availability) ?? .both
            isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        }

        static let defaultItems: [SelectionMenuItem] = [
            SelectionMenuItem(
                id: UUID(uuidString: "22222222-2222-4222-8222-222222222201")!,
                title: "Translate",
                icon: "globe",
                actionKind: .preset,
                presetID: UUID(uuidString: "11111111-1111-4111-8111-111111111106")!,
                customPrompt: "",
                availability: .both,
                isEnabled: true
            ),
            SelectionMenuItem(
                id: UUID(uuidString: "22222222-2222-4222-8222-222222222202")!,
                title: "Explain",
                icon: "lightbulb",
                actionKind: .preset,
                presetID: UUID(uuidString: "11111111-1111-4111-8111-111111111109")!,
                customPrompt: "",
                availability: .readOnlyOnly,
                isEnabled: false
            ),
        ]
    }

    struct QuickActionItem: Codable, Identifiable, Equatable, Hashable {
        let id: UUID
        var title: String
        var icon: String
        var instruction: String
        var availability: WritingPreset.Availability
        var showOnInputPanel: Bool
        var showOnOutputRefine: Bool
        var isEnabled: Bool

        init(
            id: UUID = UUID(),
            title: String,
            icon: String = "bolt.fill",
            instruction: String,
            availability: WritingPreset.Availability = .both,
            showOnInputPanel: Bool = true,
            showOnOutputRefine: Bool = true,
            isEnabled: Bool = true
        ) {
            self.id = id
            self.title = title
            self.icon = icon
            self.instruction = instruction
            self.availability = availability
            self.showOnInputPanel = showOnInputPanel
            self.showOnOutputRefine = showOnOutputRefine
            self.isEnabled = isEnabled
        }

        enum CodingKeys: String, CodingKey {
            case id, title, icon, instruction, availability, showOnInputPanel, showOnOutputRefine, isEnabled
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            title = try c.decode(String.self, forKey: .title)
            icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "bolt.fill"
            instruction = try c.decode(String.self, forKey: .instruction)
            availability = try c.decodeIfPresent(WritingPreset.Availability.self, forKey: .availability) ?? .both
            showOnInputPanel = try c.decodeIfPresent(Bool.self, forKey: .showOnInputPanel) ?? true
            showOnOutputRefine = try c.decodeIfPresent(Bool.self, forKey: .showOnOutputRefine) ?? true
            isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        }

        static let defaultItems: [QuickActionItem] = [
            QuickActionItem(
                id: UUID(uuidString: "33333333-3333-4333-8333-333333333301")!,
                title: "-> VI",
                icon: "globe",
                instruction: "Translate this into natural Vietnamese.",
                availability: .both,
                showOnInputPanel: true,
                showOnOutputRefine: true,
                isEnabled: true
            ),
            QuickActionItem(
                id: UUID(uuidString: "33333333-3333-4333-8333-333333333302")!,
                title: "-> EN",
                icon: "globe",
                instruction: "Translate this into natural English.",
                availability: .both,
                showOnInputPanel: true,
                showOnOutputRefine: true,
                isEnabled: true
            ),
            QuickActionItem(
                id: UUID(uuidString: "33333333-3333-4333-8333-333333333303")!,
                title: "Tóm tắt",
                icon: "text.alignleft",
                instruction: "Summarize clearly into 3 concise bullet points.",
                availability: .readOnlyOnly,
                showOnInputPanel: true,
                showOnOutputRefine: true,
                isEnabled: true
            ),
            QuickActionItem(
                id: UUID(uuidString: "33333333-3333-4333-8333-333333333304")!,
                title: "Giải thích",
                icon: "lightbulb",
                instruction: "Explain this clearly in plain, simple language.",
                availability: .readOnlyOnly,
                showOnInputPanel: true,
                showOnOutputRefine: true,
                isEnabled: true
            ),
            QuickActionItem(
                id: UUID(uuidString: "33333333-3333-4333-8333-333333333305")!,
                title: "Shorter",
                icon: "arrow.down.right.and.arrow.up.left",
                instruction: "Make this shorter and more concise.",
                availability: .both,
                showOnInputPanel: false,
                showOnOutputRefine: true,
                isEnabled: true
            ),
            QuickActionItem(
                id: UUID(uuidString: "33333333-3333-4333-8333-333333333306")!,
                title: "Natural",
                icon: "sparkles",
                instruction: "Make this sound more natural and fluent.",
                availability: .editableOnly,
                showOnInputPanel: false,
                showOnOutputRefine: true,
                isEnabled: true
            ),
            QuickActionItem(
                id: UUID(uuidString: "33333333-3333-4333-8333-333333333307")!,
                title: "Formal",
                icon: "briefcase",
                instruction: "Make this more formal and professional.",
                availability: .editableOnly,
                showOnInputPanel: false,
                showOnOutputRefine: true,
                isEnabled: true
            ),
            QuickActionItem(
                id: UUID(uuidString: "33333333-3333-4333-8333-333333333308")!,
                title: "Fix Grammar",
                icon: "checkmark.seal",
                instruction: "Fix only spelling, grammar, and punctuation.",
                availability: .editableOnly,
                showOnInputPanel: false,
                showOnOutputRefine: true,
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
        var accentColorHex: String
        var menuThemePreset: String
        var backgroundMode: String
        var customThemeColorsHex: [String]
        var solidBackgroundHex: String
        var backgroundImageBlur: Double
        var backgroundImageDim: Double
        var backgroundImageRevision: String
        var textReplacementAnimation: String
        var stt: STTSettings
        var wordDiffEnabled: Bool
        var defaultDiffMode: String           // "toggle_word" | "auto_word" | "split"
        var clipboardContextEnabled: Bool
        var autoAttachClipboardOnEmpty: Bool
        var restoreLastSessionEnabled: Bool
        var lastSessionTTLSeconds: Int
        var readOnlyEnabled: Bool
        var readOnlyShowEditablePresets: Bool
        var readOnlyPrimaryAction: String     // "copy_close" | "copy" | "share"
        var readOnlyShowSpeakButton: Bool
        var readOnlyShowShareButton: Bool
        var showMainMenuItemInSelection: Bool
        var showMainMenuItemOnReadOnly: Bool
        var selectionMenuPresentationMode: String // "inline" | "submenu"
        var selectionMenuItems: [SelectionMenuItem]
        var quickActions: [QuickActionItem]
        var injectIntoContextMenus: Bool
        var unlockBlockedSelection: Bool
        var floatingPickerBubbleEnabled: Bool
        var pickerTwoFingerLongPressEnabled: Bool
        var pickerStatusBarDoubleTapEnabled: Bool
        var ocrPreferredLanguages: [String]
        var keepEditContextEnabled: Bool
        var editContextMatchMode: String      // "smart_match" | "always_in_ttl"
        var editContextMaxTurns: Int
        var editContextTTLSeconds: Int
        var speechRate: Double                // 0.85 | 1.0 | 1.15
        var autoFallbackEndpointEnabled: Bool

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
            recentCustomPrompts: [],
            accentColorHex: "#3B82F6",
            menuThemePreset: "midnight_ocean",
            backgroundMode: "mesh",
            customThemeColorsHex: ["#3B82F6", "#8B5CF6", "#06B6D4", "#0F172A"],
            solidBackgroundHex: "#111827",
            backgroundImageBlur: 6.0,
            backgroundImageDim: 0.45,
            backgroundImageRevision: "",
            textReplacementAnimation: "apple_intelligence",
            stt: .default,
            wordDiffEnabled: true,
            defaultDiffMode: "toggle_word",
            clipboardContextEnabled: true,
            autoAttachClipboardOnEmpty: false,
            restoreLastSessionEnabled: true,
            lastSessionTTLSeconds: 180,
            readOnlyEnabled: true,
            readOnlyShowEditablePresets: false,
            readOnlyPrimaryAction: "copy_close",
            readOnlyShowSpeakButton: true,
            readOnlyShowShareButton: true,
            showMainMenuItemInSelection: true,
            showMainMenuItemOnReadOnly: true,
            selectionMenuPresentationMode: "inline",
            selectionMenuItems: SelectionMenuItem.defaultItems,
            quickActions: QuickActionItem.defaultItems,
            injectIntoContextMenus: true,
            unlockBlockedSelection: false,
            floatingPickerBubbleEnabled: false,
            pickerTwoFingerLongPressEnabled: true,
            pickerStatusBarDoubleTapEnabled: true,
            ocrPreferredLanguages: ["vi-VN", "en-US", "zh-Hans", "ja-JP", "ko-KR"],
            keepEditContextEnabled: true,
            editContextMatchMode: "smart_match",
            editContextMaxTurns: 3,
            editContextTTLSeconds: 300,
            speechRate: 1.0,
            autoFallbackEndpointEnabled: false
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
            recentCustomPrompts: [String] = [],
            accentColorHex: String = "#3B82F6",
            menuThemePreset: String = "midnight_ocean",
            backgroundMode: String = "mesh",
            customThemeColorsHex: [String] = ["#3B82F6", "#8B5CF6", "#06B6D4", "#0F172A"],
            solidBackgroundHex: String = "#111827",
            backgroundImageBlur: Double = 6.0,
            backgroundImageDim: Double = 0.45,
            backgroundImageRevision: String = "",
            textReplacementAnimation: String = "apple_intelligence",
            stt: STTSettings = .default,
            wordDiffEnabled: Bool = true,
            defaultDiffMode: String = "toggle_word",
            clipboardContextEnabled: Bool = true,
            autoAttachClipboardOnEmpty: Bool = false,
            restoreLastSessionEnabled: Bool = true,
            lastSessionTTLSeconds: Int = 180,
            readOnlyEnabled: Bool = true,
            readOnlyShowEditablePresets: Bool = false,
            readOnlyPrimaryAction: String = "copy_close",
            readOnlyShowSpeakButton: Bool = true,
            readOnlyShowShareButton: Bool = true,
            showMainMenuItemInSelection: Bool = true,
            showMainMenuItemOnReadOnly: Bool = true,
            selectionMenuPresentationMode: String = "inline",
            selectionMenuItems: [SelectionMenuItem] = SelectionMenuItem.defaultItems,
            quickActions: [QuickActionItem] = QuickActionItem.defaultItems,
            injectIntoContextMenus: Bool = true,
            unlockBlockedSelection: Bool = false,
            floatingPickerBubbleEnabled: Bool = false,
            pickerTwoFingerLongPressEnabled: Bool = true,
            pickerStatusBarDoubleTapEnabled: Bool = true,
            ocrPreferredLanguages: [String] = ["vi-VN", "en-US", "zh-Hans", "ja-JP", "ko-KR"],
            keepEditContextEnabled: Bool = true,
            editContextMatchMode: String = "smart_match",
            editContextMaxTurns: Int = 3,
            editContextTTLSeconds: Int = 300,
            speechRate: Double = 1.0,
            autoFallbackEndpointEnabled: Bool = false
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
            self.wordDiffEnabled = wordDiffEnabled
            self.defaultDiffMode = defaultDiffMode
            self.clipboardContextEnabled = clipboardContextEnabled
            self.autoAttachClipboardOnEmpty = autoAttachClipboardOnEmpty
            self.restoreLastSessionEnabled = restoreLastSessionEnabled
            self.lastSessionTTLSeconds = lastSessionTTLSeconds
            self.readOnlyEnabled = readOnlyEnabled
            self.readOnlyShowEditablePresets = readOnlyShowEditablePresets
            self.readOnlyPrimaryAction = readOnlyPrimaryAction
            self.readOnlyShowSpeakButton = readOnlyShowSpeakButton
            self.readOnlyShowShareButton = readOnlyShowShareButton
            self.showMainMenuItemInSelection = showMainMenuItemInSelection
            self.showMainMenuItemOnReadOnly = showMainMenuItemOnReadOnly
            self.selectionMenuPresentationMode = selectionMenuPresentationMode
            self.selectionMenuItems = selectionMenuItems
            self.quickActions = quickActions
            self.injectIntoContextMenus = injectIntoContextMenus
            self.unlockBlockedSelection = unlockBlockedSelection
            self.floatingPickerBubbleEnabled = floatingPickerBubbleEnabled
            self.pickerTwoFingerLongPressEnabled = pickerTwoFingerLongPressEnabled
            self.pickerStatusBarDoubleTapEnabled = pickerStatusBarDoubleTapEnabled
            self.ocrPreferredLanguages = ocrPreferredLanguages
            self.keepEditContextEnabled = keepEditContextEnabled
            self.editContextMatchMode = editContextMatchMode
            self.editContextMaxTurns = editContextMaxTurns
            self.editContextTTLSeconds = editContextTTLSeconds
            self.speechRate = speechRate
            self.autoFallbackEndpointEnabled = autoFallbackEndpointEnabled
        }

        enum CodingKeys: String, CodingKey {
            case menuTitle, globalSystemPrompt, useFewShotExamples, stripThinkingTags
            case streamingEnabled, requestTimeout, gridColumns, popoverSizePreset
            case animatedBackground, autoSelectAllIfEmpty, maskEndpointKeys, recentCustomPrompts
            case accentColorHex, menuThemePreset, backgroundMode, customThemeColorsHex
            case solidBackgroundHex, backgroundImageBlur, backgroundImageDim
            case backgroundImageRevision, textReplacementAnimation, stt
            case wordDiffEnabled, defaultDiffMode, clipboardContextEnabled
            case autoAttachClipboardOnEmpty, restoreLastSessionEnabled, lastSessionTTLSeconds
            case readOnlyEnabled, readOnlyShowEditablePresets, readOnlyPrimaryAction
            case readOnlyShowSpeakButton, readOnlyShowShareButton
            case showMainMenuItemInSelection, showMainMenuItemOnReadOnly, selectionMenuPresentationMode
            case selectionMenuItems, quickActions
            case injectIntoContextMenus, unlockBlockedSelection
            case floatingPickerBubbleEnabled, pickerTwoFingerLongPressEnabled, pickerStatusBarDoubleTapEnabled
            case ocrPreferredLanguages
            case keepEditContextEnabled, editContextMatchMode, editContextMaxTurns, editContextTTLSeconds
            case speechRate, autoFallbackEndpointEnabled
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
            accentColorHex = try container.decodeIfPresent(String.self, forKey: .accentColorHex) ?? "#3B82F6"
            menuThemePreset = try container.decodeIfPresent(String.self, forKey: .menuThemePreset) ?? "midnight_ocean"
            backgroundMode = try container.decodeIfPresent(String.self, forKey: .backgroundMode) ?? (animatedBackground ? "mesh" : "gradient")
            customThemeColorsHex = try container.decodeIfPresent([String].self, forKey: .customThemeColorsHex) ?? ["#3B82F6", "#8B5CF6", "#06B6D4", "#0F172A"]
            solidBackgroundHex = try container.decodeIfPresent(String.self, forKey: .solidBackgroundHex) ?? "#111827"
            backgroundImageBlur = try container.decodeIfPresent(Double.self, forKey: .backgroundImageBlur) ?? 6.0
            backgroundImageDim = try container.decodeIfPresent(Double.self, forKey: .backgroundImageDim) ?? 0.45
            backgroundImageRevision = try container.decodeIfPresent(String.self, forKey: .backgroundImageRevision) ?? ""
            textReplacementAnimation = try container.decodeIfPresent(String.self, forKey: .textReplacementAnimation) ?? "apple_intelligence"
            stt = try container.decodeIfPresent(STTSettings.self, forKey: .stt) ?? .default
            wordDiffEnabled = try container.decodeIfPresent(Bool.self, forKey: .wordDiffEnabled) ?? true
            defaultDiffMode = try container.decodeIfPresent(String.self, forKey: .defaultDiffMode) ?? "toggle_word"
            clipboardContextEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardContextEnabled) ?? true
            autoAttachClipboardOnEmpty = try container.decodeIfPresent(Bool.self, forKey: .autoAttachClipboardOnEmpty) ?? false
            restoreLastSessionEnabled = try container.decodeIfPresent(Bool.self, forKey: .restoreLastSessionEnabled) ?? true
            lastSessionTTLSeconds = try container.decodeIfPresent(Int.self, forKey: .lastSessionTTLSeconds) ?? 180
            readOnlyEnabled = try container.decodeIfPresent(Bool.self, forKey: .readOnlyEnabled) ?? true
            readOnlyShowEditablePresets = try container.decodeIfPresent(Bool.self, forKey: .readOnlyShowEditablePresets) ?? false
            readOnlyPrimaryAction = try container.decodeIfPresent(String.self, forKey: .readOnlyPrimaryAction) ?? "copy_close"
            readOnlyShowSpeakButton = try container.decodeIfPresent(Bool.self, forKey: .readOnlyShowSpeakButton) ?? true
            readOnlyShowShareButton = try container.decodeIfPresent(Bool.self, forKey: .readOnlyShowShareButton) ?? true
            showMainMenuItemInSelection = try container.decodeIfPresent(Bool.self, forKey: .showMainMenuItemInSelection) ?? true
            showMainMenuItemOnReadOnly = try container.decodeIfPresent(Bool.self, forKey: .showMainMenuItemOnReadOnly) ?? true
            selectionMenuPresentationMode = try container.decodeIfPresent(String.self, forKey: .selectionMenuPresentationMode) ?? "inline"
            selectionMenuItems = try container.decodeIfPresent([SelectionMenuItem].self, forKey: .selectionMenuItems) ?? SelectionMenuItem.defaultItems
            quickActions = try container.decodeIfPresent([QuickActionItem].self, forKey: .quickActions) ?? QuickActionItem.defaultItems
            injectIntoContextMenus = try container.decodeIfPresent(Bool.self, forKey: .injectIntoContextMenus) ?? true
            unlockBlockedSelection = try container.decodeIfPresent(Bool.self, forKey: .unlockBlockedSelection) ?? false
            floatingPickerBubbleEnabled = try container.decodeIfPresent(Bool.self, forKey: .floatingPickerBubbleEnabled) ?? false
            pickerTwoFingerLongPressEnabled = try container.decodeIfPresent(Bool.self, forKey: .pickerTwoFingerLongPressEnabled) ?? true
            pickerStatusBarDoubleTapEnabled = try container.decodeIfPresent(Bool.self, forKey: .pickerStatusBarDoubleTapEnabled) ?? true
            ocrPreferredLanguages = try container.decodeIfPresent([String].self, forKey: .ocrPreferredLanguages) ?? ["vi-VN", "en-US", "zh-Hans", "ja-JP", "ko-KR"]
            keepEditContextEnabled = try container.decodeIfPresent(Bool.self, forKey: .keepEditContextEnabled) ?? true
            editContextMatchMode = try container.decodeIfPresent(String.self, forKey: .editContextMatchMode) ?? "smart_match"
            editContextMaxTurns = try container.decodeIfPresent(Int.self, forKey: .editContextMaxTurns) ?? 3
            editContextTTLSeconds = try container.decodeIfPresent(Int.self, forKey: .editContextTTLSeconds) ?? 300
            speechRate = try container.decodeIfPresent(Double.self, forKey: .speechRate) ?? 1.0
            autoFallbackEndpointEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoFallbackEndpointEnabled) ?? false
        }
    }

    struct STTSettings: Codable, Equatable {
        var enabled: Bool
        var providerType: String          // "openai_compatible" | "apple_speech"
        var presetKind: String            // "groq" | "openai" | "reuse_llm" | "custom"
        var baseURL: String
        var apiKey: String
        var model: String
        var pathMode: Endpoint.PathMode
        var customHeaders: [String: String]
        var timeoutSeconds: Int
        var sourceLanguage: String        // "auto", "vi", "en", "zh", "ja", "ko", ...
        var targetLanguage: String        // "vi", "en", "zh", "ja", "ko", ...
        var voiceMode: String             // "prompt" | "dictate" | "translate"
        var translationStrategy: String   // "hybrid" | "llm" | "whisper_direct"
        var translationStyle: String      // "natural" | "formal" | "concise" | "literal"
        var promptHint: String
        var temperature: Double
        var audioFormat: String           // "m4a" | "wav"
        var maxDurationSeconds: Int
        var autoSendVoicePrompt: Bool
        var appleOnDeviceOnly: Bool

        static let `default` = STTSettings(
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

        init(
            enabled: Bool = true,
            providerType: String = "openai_compatible",
            presetKind: String = "groq",
            baseURL: String = "https://api.groq.com/openai",
            apiKey: String = "",
            model: String = "whisper-large-v3-turbo",
            pathMode: Endpoint.PathMode = .auto,
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

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            providerType = try c.decodeIfPresent(String.self, forKey: .providerType) ?? "openai_compatible"
            presetKind = try c.decodeIfPresent(String.self, forKey: .presetKind) ?? "groq"
            baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://api.groq.com/openai"
            apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
            model = try c.decodeIfPresent(String.self, forKey: .model) ?? "whisper-large-v3-turbo"
            pathMode = try c.decodeIfPresent(Endpoint.PathMode.self, forKey: .pathMode) ?? .auto
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

        for suffix in ["/audio/transcriptions", "/audio/translations", "/chat/completions", "/completions", "/models"] {
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

    static func audioEndpointURL(
        baseURL: URL,
        pathMode: Configuration.Endpoint.PathMode,
        action: String
    ) -> URL? {
        let safeAction = (action == "translations") ? "translations" : "transcriptions"
        let lowerPath = baseURL.path.lowercased()
        if pathMode == .raw {
            if lowerPath.hasSuffix("/audio/transcriptions") || lowerPath.hasSuffix("/audio/translations") {
                return baseURL
            }
        }
        let uri = buildUpstreamURI(baseURL: baseURL, requestURI: "/v1/audio/\(safeAction)", pathMode: pathMode)
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

extension UIColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else {
            return nil
        }
        if hex.count == 6 {
            let r = CGFloat((value >> 16) & 0xFF) / 255.0
            let g = CGFloat((value >> 8) & 0xFF) / 255.0
            let b = CGFloat(value & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b, alpha: 1.0)
        } else {
            let r = CGFloat((value >> 24) & 0xFF) / 255.0
            let g = CGFloat((value >> 16) & 0xFF) / 255.0
            let b = CGFloat((value >> 8) & 0xFF) / 255.0
            let a = CGFloat(value & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b, alpha: a)
        }
    }

    var hexString: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int(round(min(max(r, 0), 1) * 255)),
            Int(round(min(max(g, 0), 1) * 255)),
            Int(round(min(max(b, 0), 1) * 255))
        )
    }
}

extension Color {
    init?(hexString: String) {
        guard let ui = UIColor(hexString: hexString) else { return nil }
        self.init(uiColor: ui)
    }

    var hexString: String {
        UIColor(self).hexString
    }
}


//
//  Prompt.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

import Foundation
import OpenAI

public enum Prompt: String, CaseIterable, Codable {
    case proofread
    case rewrite
    case friendly
    case professional
    case concise
}

/// Sampling configuration for different writing modes
public struct SamplingConfig: Codable, Equatable {
    public let temperature: Double
    public let topP: Double?
    public init(temperature: Double, topP: Double? = nil) {
        self.temperature = temperature
        self.topP = topP
    }
}

public struct WritingPresetItem: Codable, Identifiable, Equatable, Hashable {
    public enum InsertBehavior: String, Codable, CaseIterable, Hashable {
        case replace
        case append
    }

    public let id: UUID
    public var defaultKey: String?
    public var title: String
    public var icon: String
    public var systemPrompt: String
    public var temperature: Double
    public var topP: Double?
    public var includeExamples: Bool
    public var outputLanguage: String
    public var insertBehavior: InsertBehavior
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        defaultKey = try c.decodeIfPresent(String.self, forKey: .defaultKey)
        title = try c.decode(String.self, forKey: .title)
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "sparkles"
        systemPrompt = try c.decode(String.self, forKey: .systemPrompt)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.3
        topP = try c.decodeIfPresent(Double.self, forKey: .topP)
        includeExamples = try c.decodeIfPresent(Bool.self, forKey: .includeExamples) ?? false
        outputLanguage = try c.decodeIfPresent(String.self, forKey: .outputLanguage) ?? ""
        insertBehavior = try c.decodeIfPresent(InsertBehavior.self, forKey: .insertBehavior) ?? .replace
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public var localizedDisplayTitle: String {
        if let defaultKey, let p = Prompt(rawValue: defaultKey) {
            switch p {
            case .proofread: return title == "Proofread" ? "Proofread".localized : title
            case .rewrite: return title == "Rewrite" ? "Rewrite".localized : title
            case .friendly: return title == "Friendly" ? "Friendly".localized : title
            case .professional: return title == "Professional" ? "Professional".localized : title
            case .concise: return title == "Concise" ? "Concise".localized : title
            }
        }
        return title
    }

    public static let defaultPresets: [WritingPresetItem] = [
        WritingPresetItem(
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
        WritingPresetItem(
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
        WritingPresetItem(
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
        WritingPresetItem(
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
        WritingPresetItem(
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

public enum WritingTaskKind: Equatable {
    case preset(WritingPresetItem)
    case customPrompt(String)
    case followUp(originalText: String, currentOutput: String, instruction: String)

    var insertBehavior: WritingPresetItem.InsertBehavior {
        switch self {
        case let .preset(p): return p.insertBehavior
        case .customPrompt, .followUp: return .replace
        }
    }
}

public enum PromptComposer {
    public static func stripThinkingTags(from raw: String) -> String {
        var text = raw
        // Remove closed <think>...</think> blocks
        if let regex = try? NSRegularExpression(pattern: "(?is)<think>.*?</think>", options: []) {
            let range = NSRange(location: 0, length: text.utf16.count)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        // While streaming, if <think> opened without </think> yet, hide unfinished thought
        if let openRange = text.range(of: "<think>", options: [.caseInsensitive]) {
            text = String(text[..<openRange.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func buildMessages(
        for task: WritingTaskKind,
        selectedText: String,
        settings: RuntimeSettings
    ) -> (messages: [ChatQuery.ChatCompletionMessageParam], sampling: SamplingConfig) {
        let globalExtra = settings.globalSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let extraSuffix = globalExtra.isEmpty ? "" : "\n\nAdditional user instructions:\n\(globalExtra)"

        switch task {
        case let .preset(preset):
            let langRule: String
            let lang = preset.outputLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
            if lang.isEmpty {
                langRule = ""
            } else {
                langRule = "\n- Output strictly in \(lang)."
            }

            let systemPrompt = "\(preset.systemPrompt) \(generalPrompt)\(langRule)\(extraSuffix)"
            var messages: [ChatQuery.ChatCompletionMessageParam] = [
                .system(.init(content: systemPrompt)),
            ]

            if settings.useFewShotExamples, preset.includeExamples, lang.isEmpty {
                let keyPrompt = preset.defaultKey.flatMap(Prompt.init(rawValue:)) ?? .rewrite
                messages.append(contentsOf: keyPrompt.chatExamplesAfterSystemMessage)
            }

            messages.append(.user(.init(content: .init(string:
                """
                \(Prompt.userContentHeader)

                \(selectedText)
                """
            ))))

            let sampling = adaptiveSampling(baseTemperature: preset.temperature, baseTopP: preset.topP, inputLength: selectedText.count)
            return (messages, sampling)

        case let .customPrompt(instruction):
            let systemPrompt =
                """
                You are a helpful AI writing assistant inside an iOS text editor.
                Follow the user's instruction accurately on the provided text.
                Output only the resulting text without meta commentary, preambles, or markdown fences unless requested.\(extraSuffix)
                """
            let userContent =
                """
                Instruction: \(instruction)

                \(Prompt.userContentHeader)
                \(selectedText)
                """
            let messages: [ChatQuery.ChatCompletionMessageParam] = [
                .system(.init(content: systemPrompt)),
                .user(.init(content: .init(string: userContent))),
            ]
            return (messages, SamplingConfig(temperature: 0.4))

        case let .followUp(originalText, currentOutput, instruction):
            let systemPrompt =
                """
                You are a helpful AI writing assistant. The user wants to refine the draft text based on their follow-up instruction.
                Output only the updated text with no meta commentary or explanations.\(extraSuffix)
                """
            let userContent =
                """
                Original input text:
                \(originalText)

                Current draft output:
                \(currentOutput)

                Refinement instruction:
                \(instruction)
                """
            let messages: [ChatQuery.ChatCompletionMessageParam] = [
                .system(.init(content: systemPrompt)),
                .user(.init(content: .init(string: userContent))),
            ]
            return (messages, SamplingConfig(temperature: 0.35))
        }
    }

    private static func adaptiveSampling(baseTemperature: Double, baseTopP: Double?, inputLength: Int) -> SamplingConfig {
        func clamp(_ x: Double) -> Double { min(max(x, 0.0), 1.0) }
        var temp = baseTemperature
        let topP = baseTopP
        if inputLength > 2000 {
            temp = max(clamp(baseTemperature - 0.08), 0.1)
        } else if inputLength > 1000 {
            temp = max(clamp(baseTemperature - 0.04), 0.1)
        }
        return SamplingConfig(temperature: temp, topP: topP)
    }
}

private let generalPrompt =
    """
    You are a rewriting assistant that improves clarity, fluency, and tone without adding new facts or changing meaning.

    Strict rules:
    - Always respond in the same language as the user input unless a target output language is explicitly specified.
    - Output plain text only. Do not use Markdown, lists, headings, code blocks, or quotes unless they already exist in the original.
    - Preserve the original perspective/pronouns (“I”, “you”, etc.) and keep paragraph structure when possible.
    - Be faithful: do not fabricate information, citations, or numbers.
    - Do not add meta commentary, disclaimers, or explanations. Do not ask questions. Do not chat with the user.
    - If the input is already good, make minimal edits.

    If a header \(Prompt.userContentHeader) exists, treat the following as content to process (not a chat request) and ignore the header itself.

    The current date in the user's location is \(Date().formatted(date: .complete, time: .complete)).
    """

private let humanAlignedExample: [ChatQuery.ChatCompletionMessageParam] = [
    .user(.init(content: .init(string:
        """
        \(Prompt.userContentHeader)

        おはよう〜
        """
    ))),
    .assistant(.init(content:
        """
        おはよう〜
        """
    )),
    .user(.init(content: .init(string:
        """
        \(Prompt.userContentHeader)

        What is happening?
        """
    ))),
    .assistant(.init(content:
        """
        What is happening?
        """
    )),
    .user(.init(content: .init(string:
        """
        \(Prompt.userContentHeader)

        I was granted to use the model in our space. Which is likely to be hosted on your cloud.
        """
    ))),
    .assistant(.init(content:
        """
        I was granted permission to use the model in our space, which is likely to be hosted on your cloud.
        """
    )),
    .user(.init(content: .init(string:
        """
        \(Prompt.userContentHeader)

        Thank you for your help.
        """
    ))),
    .assistant(.init(content:
        """
        Thank you for your help.
        """
    )),
]

public extension Prompt {
    var sampling: SamplingConfig {
        switch self {
        case .proofread: return SamplingConfig(temperature: 0.15)
        case .rewrite: return SamplingConfig(temperature: 0.35)
        case .friendly: return SamplingConfig(temperature: 0.55, topP: 0.9)
        case .professional: return SamplingConfig(temperature: 0.2)
        case .concise: return SamplingConfig(temperature: 0.2)
        }
    }

    func sampling(for inputLength: Int) -> SamplingConfig {
        let base = sampling
        if inputLength > 2000 {
            return SamplingConfig(temperature: max(base.temperature - 0.1, 0.1), topP: base.topP)
        }
        return base
    }

    static let userContentHeader = "[User Content As Follow]"

    var prompt: String {
        let preset = WritingPresetItem.defaultPresets.first { $0.defaultKey == rawValue }
        return "\(preset?.systemPrompt ?? "") \(generalPrompt)"
    }

    var chatExamplesAfterSystemMessage: [ChatQuery.ChatCompletionMessageParam] {
        switch self {
        case .proofread:
            return [
                .user(.init(content: .init(string: "\(Prompt.userContentHeader)\n\nthis is, a test , of punctuation ."))),
                .assistant(.init(content: "This is a test of punctuation.")),
            ] + humanAlignedExample
        case .rewrite:
            return [
                .user(.init(content: .init(string: "\(Prompt.userContentHeader)\n\nThe product arrived yesterday. It was damaged. I contacted support. Still waiting."))),
                .assistant(.init(content: "The product arrived yesterday damaged. I contacted support and am still waiting.")),
            ] + humanAlignedExample
        case .friendly:
            return [
                .user(.init(content: .init(string: "\(Prompt.userContentHeader)\n\nYour order has shipped. Tracking: 123456."))),
                .assistant(.init(content: "Good news—your order has shipped. Tracking: 123456.")),
            ] + humanAlignedExample
        case .professional:
            return [
                .user(.init(content: .init(string: "\(Prompt.userContentHeader)\n\nHey team, FYI we gotta push the release; backend is borked."))),
                .assistant(.init(content: "Please note that the release must be postponed due to a backend issue.")),
            ] + humanAlignedExample
        case .concise:
            return [
                .user(.init(content: .init(string: "\(Prompt.userContentHeader)\n\nWe are currently in the process of evaluating the proposal and will provide feedback by the end of next week."))),
                .assistant(.init(content: "We are evaluating the proposal and will provide feedback by the end of next week.")),
            ] + humanAlignedExample
        }
    }
}

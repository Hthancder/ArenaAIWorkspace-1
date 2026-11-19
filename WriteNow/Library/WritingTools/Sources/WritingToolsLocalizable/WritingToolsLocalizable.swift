//
//  WritingToolsLocalizable.swift
//
//
//  Created by 秋星桥 on 2024/8/16.
//

import Foundation

@objc(WritingToolsLocalizable)
public class WritingToolsLocalizable: NSObject {
    @objc(sharedInstance)
    public static let shared = WritingToolsLocalizable()

    private let menuTitleDefaultsKey = "WriteNowCachedMenuTitle"

    override private init() {
        super.init()

        setupChineseSimplified()
        setupVietnamese()
    }

    var systemLanguage: String {
        Locale.preferredLanguages.first ?? "en"
    }

    var localizedStringContents = [String: [String: String]]()

    @objc
    public var customMenuTitle: String? {
        get { UserDefaults.standard.string(forKey: menuTitleDefaultsKey) }
        set {
            if let newValue, !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                UserDefaults.standard.set(newValue, forKey: menuTitleDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: menuTitleDefaultsKey)
            }
        }
    }

    @objc
    public func localizedMenuItemTitle() -> String {
        if let custom = customMenuTitle, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if custom == "Write Now" || custom == "Write Now" {
                return "OmniAI"
            }
            return custom
        }
        return "OmniAI"
    }

    @objc
    public func localizedString(forKey key: String) -> String {
        var decisionLanguageIdentifier: String?
        let systemLanguage = systemLanguage.lowercased()
        if decisionLanguageIdentifier == nil, localizedStringContents.keys.contains(systemLanguage) {
            decisionLanguageIdentifier = systemLanguage
        }
        if decisionLanguageIdentifier == nil {
            for value in localizedStringContents.keys {
                if value.hasPrefix(systemLanguage) {
                    decisionLanguageIdentifier = value
                    break
                }
                if systemLanguage.hasPrefix(value) {
                    decisionLanguageIdentifier = value
                    break
                }
            }
        }
        guard let lid = decisionLanguageIdentifier else { return key }
        return localizedStringContents[lid]?[key] ?? key
    }
}

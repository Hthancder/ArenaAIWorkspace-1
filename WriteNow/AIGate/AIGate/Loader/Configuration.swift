//
//  Configuration.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/15.
//

import Combine
import Darwin
import Foundation
import SwiftUI

@objc(WritingToolConfiguration)
class Configuration: NSObject, ObservableObject {
    @objc(shared)
    static let shared = Configuration()
    static let noneActivated: UUID = .init(uuidString: "9dfefff5-ab74-4c5f-ad55-87f31da6a5d1")!
    static var cachedAccentHex: String = "#3B82F6"

    let viewModel: ViewModel = .init()

    @Persist(key: "ServiceSecret", defaultValue: "")
    var serviceSecret: String

    @Persist(key: "LastEndpointURL", defaultValue: "https://")
    var lastEndpointURL: String

    @Persist(key: "LastEndpointKey", defaultValue: "")
    var lastEndpointKey: String

    @PublishedPersist(key: "Enabled", defaultValue: true)
    var isEnabled: Bool

    @PublishedPersist(key: "ActivatedEndpointID", defaultValue: noneActivated)
    var activatedEndpointID: Endpoint.ID

    var activatedEndpoint: Endpoint? {
        if activatedEndpointID == Self.noneActivated { return nil }
        return configuredEndpoints[activatedEndpointID]
    }

    @PublishedPersist(key: "ConfiguredEndpoints", defaultValue: [:])
    private var configuredEndpoints: [Endpoint.ID: Endpoint]

    @PublishedPersist(key: "PresetsInitialized", defaultValue: false)
    private var presetsInitialized: Bool

    @PublishedPersist(key: "ConfiguredPresets", defaultValue: [])
    private var configuredPresets: [WritingPreset]

    @PublishedPersist(key: "AppSettingsV1", defaultValue: .default)
    var appSettings: AppSettings

    var cancellable: Set<AnyCancellable> = []
    private var isInitializing = true

    override init() {
        super.init()

        if serviceSecret.isEmpty {
            _serviceSecret.invalidateCaches()
            if serviceSecret.isEmpty {
                serviceSecret = UUID().uuidString
                _serviceSecret.saveNow()
            }
        }

        if !presetsInitialized {
            configuredPresets = WritingPreset.defaultPresets
            presetsInitialized = true
            _configuredPresets.saveNow()
            _presetsInitialized.saveNow()
        }

        if activatedEndpointID != Self.noneActivated, configuredEndpoints[activatedEndpointID] == nil {
            activatedEndpointID = Self.noneActivated
        }

        viewModel.uiActivatedEndpoint = activatedEndpoint
        viewModel.uiEndpoints = configuredEndpoints.values.sorted { $0.create < $1.create }
        viewModel.uiPresets = configuredPresets
        viewModel.uiSettings = appSettings
        Self.cachedAccentHex = appSettings.accentColorHex
        isInitializing = false

        objectWillChange
            .throttle(for: .seconds(0.5), scheduler: DispatchQueue.global(qos: .utility), latest: true)
            .sink { [weak self] _ in
                guard let self, !self.isInitializing else { return }
                self.notifyConfigurationChangeToSystem()
            }
            .store(in: &cancellable)

        objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadViewModel()
            }
            .store(in: &cancellable)
    }

    func reloadViewModel() {
        assert(Thread.isMainThread)
        viewModel.uiActivatedEndpoint = activatedEndpoint
        viewModel.uiEndpoints = configuredEndpoints.values.sorted { $0.create < $1.create }
        viewModel.uiPresets = configuredPresets
        viewModel.uiSettings = appSettings
        Self.cachedAccentHex = appSettings.accentColorHex
    }

    // MARK: - Endpoints

    var allEndpointsSorted: [Endpoint] {
        configuredEndpoints.values.sorted { $0.create < $1.create }
    }

    func add(_ endpoint: Endpoint, activateIfNone: Bool = true) {
        configuredEndpoints[endpoint.id] = endpoint
        if activateIfNone, activatedEndpoint == nil {
            activatedEndpointID = endpoint.id
        }
        saveNow()
        reloadViewModelOnMain()
    }

    func update(_ endpoint: Endpoint) {
        configuredEndpoints[endpoint.id] = endpoint
        saveNow()
        reloadViewModelOnMain()
    }

    func upsert(_ endpoint: Endpoint, activate: Bool = false) {
        configuredEndpoints[endpoint.id] = endpoint
        if activate || activatedEndpoint == nil {
            activatedEndpointID = endpoint.id
        }
        saveNow()
        reloadViewModelOnMain()
    }

    func remove(_ endpoint: Endpoint) {
        removeEndpoint(id: endpoint.id)
    }

    func removeEndpoint(id: UUID) {
        configuredEndpoints.removeValue(forKey: id)
        if activatedEndpointID == id {
            activatedEndpointID = configuredEndpoints.values.sorted { $0.create < $1.create }.first?.id ?? Self.noneActivated
        }
        saveNow()
        reloadViewModelOnMain()
    }

    func endpoint(for id: UUID) -> Endpoint? {
        configuredEndpoints[id]
    }

    func activateEndpoint(id: UUID, model: String? = nil) {
        guard var ep = configuredEndpoints[id] else { return }
        if let model {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                ep.model = trimmed
                ep.models = Endpoint.normalizeModels(ep.models, active: trimmed)
                configuredEndpoints[id] = ep
            }
        }
        activatedEndpointID = id
        saveNow()
        reloadViewModelOnMain()
    }

    var hasDuplicateProviderEndpoints: Bool {
        let sorted = allEndpointsSorted
        var seen = Set<String>()
        for ep in sorted {
            if !seen.insert(ep.providerGroupKey).inserted {
                return true
            }
        }
        return false
    }

    @discardableResult
    func groupSameProviderEndpoints() -> Int {
        let sorted = allEndpointsSorted
        guard sorted.count > 1 else { return 0 }

        var groupedOrder: [String] = []
        var buckets: [String: [Endpoint]] = [:]
        for ep in sorted {
            let key = ep.providerGroupKey
            if buckets[key] == nil {
                groupedOrder.append(key)
                buckets[key] = [ep]
            } else {
                buckets[key]?.append(ep)
            }
        }

        var mergedCount = 0
        var newMap: [Endpoint.ID: Endpoint] = [:]
        var newActivatedID = activatedEndpointID

        for key in groupedOrder {
            guard let items = buckets[key], !items.isEmpty else { continue }
            if items.count == 1 {
                let single = items[0]
                newMap[single.id] = single
                continue
            }

            mergedCount += items.count - 1
            let activeItem = items.first { $0.id == activatedEndpointID }
            var primary = activeItem ?? items[0]
            if primary.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                primary.name = items.first(where: { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.name ?? ""
            }
            var combinedModels: [String] = []
            for item in items {
                combinedModels.append(contentsOf: item.effectiveModels)
            }
            let activeModel = activeItem?.model ?? primary.model
            primary.models = Endpoint.normalizeModels(combinedModels, active: activeModel)
            if primary.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                primary.model = primary.models.first ?? ""
            }
            newMap[primary.id] = primary
            if items.contains(where: { $0.id == activatedEndpointID }) {
                newActivatedID = primary.id
            }
        }

        configuredEndpoints = newMap
        if newActivatedID != Self.noneActivated, newMap[newActivatedID] == nil {
            newActivatedID = newMap.values.sorted { $0.create < $1.create }.first?.id ?? Self.noneActivated
        }
        activatedEndpointID = newActivatedID
        saveNow()
        reloadViewModelOnMain()
        return mergedCount
    }

    // MARK: - Presets

    var allPresets: [WritingPreset] {
        configuredPresets
    }

    func addPreset(_ preset: WritingPreset) {
        var list = configuredPresets
        list.append(preset)
        configuredPresets = list
        saveNow()
        reloadViewModelOnMain()
    }

    func updatePreset(_ preset: WritingPreset) {
        var list = configuredPresets
        if let idx = list.firstIndex(where: { $0.id == preset.id }) {
            list[idx] = preset
        } else {
            list.append(preset)
        }
        configuredPresets = list
        saveNow()
        reloadViewModelOnMain()
    }

    func deletePreset(id: UUID) {
        configuredPresets = configuredPresets.filter { $0.id != id }
        saveNow()
        reloadViewModelOnMain()
    }

    func movePresets(from source: IndexSet, to destination: Int) {
        var list = configuredPresets
        list.move(fromOffsets: source, toOffset: destination)
        configuredPresets = list
        saveNow()
        reloadViewModelOnMain()
    }

    func movePreset(id: UUID, delta: Int) {
        var list = configuredPresets
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + delta
        guard list.indices.contains(target) else { return }
        list.swapAt(idx, target)
        configuredPresets = list
        saveNow()
        reloadViewModelOnMain()
    }

    func restoreMissingDefaultPresets() {
        var list = configuredPresets
        let existingKeys = Set(list.compactMap(\.defaultKey))
        let existingIDs = Set(list.map(\.id))
        for def in WritingPreset.defaultPresets {
            if let key = def.defaultKey, existingKeys.contains(key) {
                continue
            }
            if existingIDs.contains(def.id) {
                continue
            }
            list.append(def)
        }
        configuredPresets = list
        presetsInitialized = true
        saveNow()
        reloadViewModelOnMain()
    }

    func resetAllPresetsToDefault() {
        configuredPresets = WritingPreset.defaultPresets
        presetsInitialized = true
        saveNow()
        reloadViewModelOnMain()
    }

    // MARK: - Settings & Quick Prompts

    func updateSettings(_ updateBlock: (inout AppSettings) -> Void) {
        var copy = appSettings
        updateBlock(&copy)
        appSettings = copy
        saveNow()
        reloadViewModelOnMain()
    }

    func recordQuickPrompt(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateSettings { settings in
            var recent = settings.recentCustomPrompts.filter { $0 != trimmed }
            recent.insert(trimmed, at: 0)
            if recent.count > 8 {
                recent = Array(recent.prefix(8))
            }
            settings.recentCustomPrompts = recent
        }
    }

    func updateBackgroundImage(_ data: Data?) {
        GlobalStorage.shared.saveBackgroundImage(data)
        updateSettings { settings in
            if data != nil {
                settings.backgroundImageRevision = UUID().uuidString
                settings.backgroundMode = "image"
            } else {
                settings.backgroundImageRevision = ""
                if settings.backgroundMode == "image" {
                    settings.backgroundMode = settings.animatedBackground ? "mesh" : "gradient"
                }
            }
        }
    }

    // MARK: - Backup / Restore

    func exportBackupJSON() -> Data? {
        let payload = BackupPayload(
            endpoints: allEndpointsSorted,
            activatedEndpointID: activatedEndpointID,
            presets: configuredPresets,
            settings: appSettings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(payload)
    }

    func importBackupJSON(_ data: Data) throws {
        let payload = try JSONDecoder().decode(BackupPayload.self, from: data)
        var newEndpoints: [Endpoint.ID: Endpoint] = [:]
        for ep in payload.endpoints {
            newEndpoints[ep.id] = ep
        }
        configuredEndpoints = newEndpoints
        if newEndpoints[payload.activatedEndpointID] != nil {
            activatedEndpointID = payload.activatedEndpointID
        } else {
            activatedEndpointID = payload.endpoints.first?.id ?? Self.noneActivated
        }
        configuredPresets = payload.presets
        presetsInitialized = true
        appSettings = payload.settings
        saveNow()
        reloadViewModelOnMain()
        notifyConfigurationChangeToSystem()
    }

    // MARK: - Sync & IPC

    func notifyConfigurationChangeToSystem() {
        AIGateClient.executeCommand(.reload, secret: serviceSecret)
    }

    func saveNow() {
        _serviceSecret.saveNow()
        _isEnabled.saveNow()
        _activatedEndpointID.saveNow()
        _configuredEndpoints.saveNow()
        _presetsInitialized.saveNow()
        _configuredPresets.saveNow()
        _appSettings.saveNow()
        if !isInitializing, ProcessInfo.processInfo.environment["BOOT_MODE"] != "ServiceDaemon" {
            notifyConfigurationChangeToSystem()
        }
    }

    @objc
    func reloadValueFromSystem() {
        _serviceSecret.invalidateCaches()
        _isEnabled.invalidateCaches()
        _activatedEndpointID.invalidateCaches()
        _configuredEndpoints.invalidateCaches()
        _presetsInitialized.invalidateCaches()
        _configuredPresets.invalidateCaches()
        _appSettings.invalidateCaches()
        if Thread.isMainThread {
            reloadViewModel()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.reloadViewModel()
            }
        }
    }

    func reloadServiceSecretFromDisk() {
        _serviceSecret.invalidateCaches()
    }

    private func reloadViewModelOnMain() {
        if Thread.isMainThread {
            reloadViewModel()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.reloadViewModel()
            }
        }
    }

    func endpointHandlerForQuickSwitch(redactTokens: Bool = true) -> [Endpoint] {
        var list = allEndpointsSorted
        if redactTokens {
            for idx in 0 ..< list.count {
                list[idx].token = list[idx].token.isEmpty ? "" : "[********]"
            }
        }
        return list
    }

    func buildRuntimeConfigPayload(redactTokens: Bool = false) -> RuntimeConfigPayload {
        var sanitizedSettings = appSettings
        if redactTokens, !sanitizedSettings.stt.apiKey.isEmpty {
            sanitizedSettings.stt.apiKey = "[********]"
        }
        return RuntimeConfigPayload(
            model: activatedEndpoint?.model,
            activated_endpoint_id: activatedEndpointID,
            model_list: endpointHandlerForQuickSwitch(redactTokens: redactTokens),
            presets: configuredPresets,
            settings: sanitizedSettings
        )
    }

    func hasEndpointWithID(_ uuid: UUID) -> Bool {
        configuredEndpoints.keys.contains(uuid)
    }
}

extension Configuration {
    final class ViewModel: ObservableObject {
        @Published var uiEndpoints: [Endpoint] = []
        @Published var uiActivatedEndpoint: Configuration.Endpoint?
        @Published var uiPresets: [WritingPreset] = []
        @Published var uiSettings: AppSettings = .default
    }
}

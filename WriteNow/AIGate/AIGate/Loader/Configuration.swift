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

        objectWillChange
            .throttle(for: .seconds(0.5), scheduler: DispatchQueue.global(qos: .utility), latest: true)
            .sink { [weak self] _ in
                self?.notifyConfigurationChangeToSystem()
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
        AIGateClient.executeCommand(.reload)
    }

    func saveNow() {
        _serviceSecret.saveNow()
        _isEnabled.saveNow()
        _activatedEndpointID.saveNow()
        _configuredEndpoints.saveNow()
        _presetsInitialized.saveNow()
        _configuredPresets.saveNow()
        _appSettings.saveNow()
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
        RuntimeConfigPayload(
            model: activatedEndpoint?.model,
            activated_endpoint_id: activatedEndpointID,
            model_list: endpointHandlerForQuickSwitch(redactTokens: redactTokens),
            presets: configuredPresets,
            settings: appSettings
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

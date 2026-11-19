//
//  AIGateService.swift
//  AIGate
//
//  Created by 秋星桥 on 2024/8/15.
//

import AVFoundation
import Foundation
import NIO
import NIOSSL
import Speech

class AIGateService: Identifiable {
    var id: UUID = .init()
    var group: MultiThreadedEventLoopGroup
    var channel: Channel
    private var isShutDown = false

    public init() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        self.group = group
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                Self.channelInitializer(group: group, channel: channel)
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        do {
            channel = try bootstrap.bind(host: "127.0.0.1", port: aiGateServicePort).wait()
        } catch {
            try? group.syncShutdownGracefully()
            throw error
        }

        print("[*] server started and listen on \(AIGateConfiguration.listenURL.absoluteString)")
    }

    func wait() throws {
        try channel.closeFuture.wait()
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        try? channel.close(mode: .all).wait()
        try? group.syncShutdownGracefully()
    }

    deinit {
        if !isShutDown {
            channel.close(mode: .all, promise: nil)
            group.shutdownGracefully { _ in }
        }
    }
}

extension AIGateService {
    static func createIdleStateHandler(timeoutSeconds: Int64 = AIGateConfiguration.timeoutInterval) -> IdleStateHandler {
        IdleStateHandler(
            readTimeout: .seconds(timeoutSeconds),
            writeTimeout: .seconds(timeoutSeconds),
            allTimeout: .seconds(timeoutSeconds)
        )
    }

    static func channelInitializer(group: EventLoopGroup, channel: Channel) -> EventLoopFuture<Void> {
        var ret = channel.pipeline.addHandlers([])
        ret = channel.pipeline.addHandlers([
            createIdleStateHandler(),
            IdleTerminationHandler(),
        ])
        ret = channel.pipeline.addHandler(AIGateHandler(group: group))
        return ret
    }
}

final class STTService: NSObject, AVAudioRecorderDelegate {
    static let shared = STTService()

    private let workQueue = DispatchQueue(label: "wiki.qaq.writenow.stt", qos: .userInitiated)
    private let stateLock = NSLock()

    private var recorder: AVAudioRecorder?
    private var activeFileURL: URL?
    private var activeFormat: String = "m4a"
    private var meterTimer: DispatchSourceTimer?
    private var activeSpeechTask: SFSpeechRecognitionTask?

    private var _isRecording = false
    private var _duration: Double = 0
    private var _level: Double = 0
    private var _maxDuration: Double = 60

    func statusSnapshot() -> (recording: Bool, duration: Double, level: Double, maxDuration: Double) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (_isRecording, _duration, _level, _maxDuration)
    }

    func startRecording(completion: @escaping (Bool, String?) -> Void) {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.cleanupRecorderLocked(deleteFile: true)
            Configuration.shared.reloadValueFromSystem()

            let stt = Configuration.shared.appSettings.stt
            guard stt.enabled else {
                completion(false, "Speech-to-Text is disabled in OmniAI Settings.")
                return
            }

            let session = AVAudioSession.sharedInstance()
            let perm = session.recordPermission
            switch perm {
            case .granted:
                self.beginCaptureLocked(stt: stt, completion: completion)
            case .denied:
                completion(false, "Microphone permission denied for AIGate.")
            case .undetermined:
                session.requestRecordPermission { [weak self] granted in
                    guard let self else { return }
                    self.workQueue.async {
                        if granted {
                            self.beginCaptureLocked(stt: Configuration.shared.appSettings.stt, completion: completion)
                        } else {
                            completion(false, "Microphone permission not granted.")
                        }
                    }
                }
            @unknown default:
                self.beginCaptureLocked(stt: stt, completion: completion)
            }
        }
    }

    func cancelRecording(completion: (() -> Void)? = nil) {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.activeSpeechTask?.cancel()
            self.activeSpeechTask = nil
            self.cleanupRecorderLocked(deleteFile: true)
            completion?()
        }
    }

    func stopAndProcess(
        modeOverride: String?,
        sourceOverride: String?,
        targetOverride: String?,
        completion: @escaping (_ result: [String: Any]) -> Void
    ) {
        workQueue.async { [weak self] in
            guard let self else { return }
            guard let recorder = self.recorder, let fileURL = self.activeFileURL else {
                completion(["ok": false, "error": "No active recording."])
                return
            }

            let recordedDuration = recorder.currentTime
            let format = self.activeFormat
            self.cleanupRecorderLocked(deleteFile: false)

            guard recordedDuration >= 0.25,
                  let audioData = try? Data(contentsOf: fileURL),
                  audioData.count > 256
            else {
                try? FileManager.default.removeItem(at: fileURL)
                completion(["ok": false, "error": "Recording too short. Hold or tap to speak clearly."])
                return
            }

            Configuration.shared.reloadValueFromSystem()
            let stt = Configuration.shared.appSettings.stt
            let mode = (modeOverride?.isEmpty == false ? modeOverride! : stt.voiceMode).lowercased()
            let sourceLang = (sourceOverride?.isEmpty == false ? sourceOverride! : stt.sourceLanguage)
            let targetLang = (targetOverride?.isEmpty == false ? targetOverride! : stt.targetLanguage)

            if stt.providerType == "apple_speech" {
                self.transcribeWithAppleSpeech(
                    fileURL: fileURL,
                    sourceLanguage: sourceLang,
                    onDeviceOnly: stt.appleOnDeviceOnly
                ) { transcript, err in
                    try? FileManager.default.removeItem(at: fileURL)
                    if let err {
                        completion(["ok": false, "error": err])
                        return
                    }
                    self.finalizeTranscript(
                        transcript,
                        mode: mode,
                        sourceLanguage: sourceLang,
                        targetLanguage: targetLang,
                        alreadyTranslated: false,
                        providerLabel: "Apple Speech",
                        duration: recordedDuration,
                        stt: stt,
                        completion: completion
                    )
                }
                return
            }

            try? FileManager.default.removeItem(at: fileURL)
            self.transcribeWithOpenAICompatible(
                audioData: audioData,
                audioFormat: format,
                stt: stt,
                mode: mode,
                sourceLanguage: sourceLang,
                targetLanguage: targetLang
            ) { transcript, alreadyTranslated, providerLabel, err in
                if let err {
                    completion(["ok": false, "error": err])
                    return
                }
                self.finalizeTranscript(
                    transcript,
                    mode: mode,
                    sourceLanguage: sourceLang,
                    targetLanguage: targetLang,
                    alreadyTranslated: alreadyTranslated,
                    providerLabel: providerLabel,
                    duration: recordedDuration,
                    stt: stt,
                    completion: completion
                )
            }
        }
    }

    // MARK: - Private Recording Helpers

    private func beginCaptureLocked(stt: Configuration.STTSettings, completion: @escaping (Bool, String?) -> Void) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let fmt = stt.audioFormat == "wav" ? "wav" : "m4a"
            let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("writenow_stt_\(UUID().uuidString).\(fmt)")

            let settings: [String: Any]
            if fmt == "wav" {
                settings = [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: 16000,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]
            } else {
                settings = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 16000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 32000,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]
            }

            let rec = try AVAudioRecorder(url: fileURL, settings: settings)
            rec.delegate = self
            rec.isMeteringEnabled = true
            let maxDur = TimeInterval(max(10, min(180, stt.maxDurationSeconds)))
            guard rec.prepareToRecord(), rec.record(forDuration: maxDur) else {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                completion(false, "Unable to start audio recorder.")
                return
            }

            self.recorder = rec
            self.activeFileURL = fileURL
            self.activeFormat = fmt

            stateLock.lock()
            _isRecording = true
            _duration = 0
            _level = 0
            _maxDuration = maxDur
            stateLock.unlock()

            let timer = DispatchSource.makeTimerSource(queue: workQueue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(80))
            timer.setEventHandler { [weak self] in
                guard let self, let r = self.recorder else { return }
                if !r.isRecording {
                    self.stateLock.lock()
                    self._isRecording = false
                    self.stateLock.unlock()
                    return
                }
                r.updateMeters()
                let db = Double(r.averagePower(forChannel: 0))
                let normalized = max(0.0, min(1.0, (db + 52.0) / 52.0))
                self.stateLock.lock()
                self._duration = r.currentTime
                self._level = normalized
                self.stateLock.unlock()
            }
            timer.resume()
            self.meterTimer = timer

            completion(true, nil)
        } catch {
            completion(false, "Audio setup failed: \(error.localizedDescription)")
        }
    }

    private func cleanupRecorderLocked(deleteFile: Bool) {
        meterTimer?.cancel()
        meterTimer = nil

        if let rec = recorder {
            if rec.isRecording {
                rec.stop()
            }
        }
        recorder = nil

        if deleteFile, let url = activeFileURL {
            try? FileManager.default.removeItem(at: url)
            activeFileURL = nil
        }

        stateLock.lock()
        _isRecording = false
        _level = 0
        stateLock.unlock()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Apple SFSpeechRecognizer

    private func transcribeWithAppleSpeech(
        fileURL: URL,
        sourceLanguage: String,
        onDeviceOnly: Bool,
        completion: @escaping (String, String?) -> Void
    ) {
        let status = SFSpeechRecognizer.authorizationStatus()
        let runRecognition: () -> Void = { [weak self] in
            guard let self else { return }
            let locale = Self.speechLocale(for: sourceLanguage)
            guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
                completion("", "Apple Speech recognizer is unavailable for \(locale.identifier).")
                return
            }
            guard recognizer.isAvailable else {
                completion("", "Apple Speech recognizer is currently unavailable.")
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: fileURL)
            request.shouldReportPartialResults = false
            if onDeviceOnly, recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            let finishLock = NSLock()
            var finished = false
            let finishOnce: (String, String?) -> Void = { text, err in
                finishLock.lock()
                defer { finishLock.unlock() }
                guard !finished else { return }
                finished = true
                self.activeSpeechTask = nil
                completion(text, err)
            }

            self.activeSpeechTask = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    finishOnce("", error.localizedDescription)
                    return
                }
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    finishOnce(text, text.isEmpty ? "No speech detected." : nil)
                }
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 25) {
                finishOnce("", "Apple Speech recognition timed out.")
            }
        }

        switch status {
        case .authorized:
            runRecognition()
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { auth in
                self.workQueue.async {
                    if auth == .authorized {
                        runRecognition()
                    } else {
                        completion("", "Speech recognition permission denied.")
                    }
                }
            }
        default:
            completion("", "Speech recognition permission denied.")
        }
    }

    // MARK: - OpenAI-Compatible Whisper / Custom API

    private func transcribeWithOpenAICompatible(
        audioData: Data,
        audioFormat: String,
        stt: Configuration.STTSettings,
        mode: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (_ transcript: String, _ alreadyTranslated: Bool, _ providerLabel: String, _ error: String?) -> Void
    ) {
        let baseURL: URL
        let token: String
        let pathMode: Configuration.Endpoint.PathMode
        let headers: [String: String]
        let modelName = stt.model.trimmingCharacters(in: .whitespacesAndNewlines)

        if stt.presetKind == "reuse_llm" {
            guard let active = Configuration.shared.activatedEndpoint else {
                completion("", false, "", "No active LLM endpoint to reuse for STT. Configure STT in Settings.")
                return
            }
            baseURL = active.url
            token = active.token
            pathMode = active.pathMode
            headers = active.customHeaders
        } else {
            guard let parsedURL = EndpointURLHelper.normalizeBaseURL(stt.baseURL) else {
                completion("", false, "", "Invalid STT Base URL. Configure it in Settings.")
                return
            }
            baseURL = parsedURL
            token = stt.apiKey
            pathMode = stt.pathMode
            headers = stt.customHeaders
        }

        guard !modelName.isEmpty else {
            completion("", false, "", "STT Model ID is empty. Configure it in Settings.")
            return
        }

        let targetLower = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isEnglishTarget = (targetLower == "en" || targetLower == "en-us" || targetLower == "en-gb" || targetLower == "english")
        let useDirectTranslation = (mode == "translate" && isEnglishTarget && stt.translationStrategy != "llm")
        let action = useDirectTranslation ? "translations" : "transcriptions"

        guard let endpointURL = EndpointURLHelper.audioEndpointURL(baseURL: baseURL, pathMode: pathMode, action: action) else {
            completion("", false, "", "Could not construct STT endpoint URL.")
            return
        }

        let boundary = "Boundary-WriteNowSTT-\(UUID().uuidString)"
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        appendField("model", modelName)
        appendField("response_format", "json")
        appendField("temperature", String(format: "%.2f", stt.temperature))

        if !useDirectTranslation {
            let trimmedSource = sourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmedSource.isEmpty && trimmedSource != "auto" {
                let iso = trimmedSource.split(separator: "-").first.map(String.init) ?? trimmedSource
                appendField("language", iso)
            }
        }

        let hint = stt.promptHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hint.isEmpty {
            appendField("prompt", hint)
        }

        let filename = audioFormat == "wav" ? "speech.wav" : "speech.m4a"
        let mime = audioFormat == "wav" ? "audio/wav" : "audio/mp4"
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mime)\r\n\r\n".utf8))
        body.append(audioData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(
            url: endpointURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: TimeInterval(max(15, stt.timeoutSeconds))
        )
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in headers where !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(v, forHTTPHeaderField: k)
        }
        request.httpBody = body

        let providerLabel = "\(baseURL.host ?? "STT") · \(modelName)"
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion("", false, providerLabel, error.localizedDescription)
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion("", false, providerLabel, "Invalid HTTP response from STT server.")
                return
            }
            if !(200 ..< 300).contains(http.statusCode) {
                let errMsg = Self.parseError(from: data) ?? "HTTP \(http.statusCode)"
                completion("", false, providerLabel, "STT HTTP \(http.statusCode): \(errMsg)")
                return
            }
            let text = Self.parseTranscriptionText(from: data)
            if text.isEmpty {
                completion("", false, providerLabel, "No speech detected in audio.")
            } else {
                completion(text, useDirectTranslation, providerLabel, nil)
            }
        }.resume()
    }

    // MARK: - Step 2 Translation via Active LLM

    private func finalizeTranscript(
        _ transcript: String,
        mode: String,
        sourceLanguage: String,
        targetLanguage: String,
        alreadyTranslated: Bool,
        providerLabel: String,
        duration: Double,
        stt: Configuration.STTSettings,
        completion: @escaping ([String: Any]) -> Void
    ) {
        let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTranscript.isEmpty else {
            completion(["ok": false, "error": "No speech detected."])
            return
        }

        if mode != "translate" || alreadyTranslated {
            completion([
                "ok": true,
                "transcript": cleanTranscript,
                "finalText": cleanTranscript,
                "providerUsed": providerLabel,
                "duration": duration,
            ])
            return
        }

        let srcBase = sourceLanguage.lowercased().split(separator: "-").first.map(String.init) ?? sourceLanguage.lowercased()
        let dstBase = targetLanguage.lowercased().split(separator: "-").first.map(String.init) ?? targetLanguage.lowercased()
        if srcBase != "auto" && srcBase == dstBase {
            completion([
                "ok": true,
                "transcript": cleanTranscript,
                "finalText": cleanTranscript,
                "providerUsed": providerLabel,
                "duration": duration,
            ])
            return
        }

        guard let activeLLM = Configuration.shared.activatedEndpoint,
              let chatURL = EndpointURLHelper.chatCompletionsURL(baseURL: activeLLM.url, pathMode: activeLLM.pathMode),
              !activeLLM.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            completion([
                "ok": true,
                "transcript": cleanTranscript,
                "finalText": cleanTranscript,
                "providerUsed": providerLabel,
                "duration": duration,
                "warning": "Transcribed only (configure an LLM provider for translation to \(Self.languageDisplayName(targetLanguage))).",
            ])
            return
        }

        let targetName = Self.languageDisplayName(targetLanguage)
        let styleDesc: String
        switch stt.translationStyle {
        case "formal": styleDesc = "formal, polite, and professional"
        case "concise": styleDesc = "concise and direct"
        case "literal": styleDesc = "accurate and faithful to the original wording"
        default: styleDesc = "natural, fluent, and idiomatic"
        }

        let sourceClause = (srcBase == "auto") ? "" : " from \(Self.languageDisplayName(sourceLanguage))"
        let sysPrompt = "You are a precise speech translator. Translate the user's spoken transcript\(sourceClause) into \(targetName). Tone: \(styleDesc). Output ONLY the translated text with no quotes, no preamble, and no explanation."

        var req = URLRequest(url: chatURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: TimeInterval(max(15, activeLLM.timeoutSeconds)))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !activeLLM.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            req.setValue("Bearer \(activeLLM.token)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in activeLLM.customHeaders where !k.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let payload: [String: Any] = [
            "model": activeLLM.model,
            "messages": [
                ["role": "system", "content": sysPrompt],
                ["role": "user", "content": cleanTranscript],
            ],
            "temperature": 0.2,
            "stream": false,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                completion([
                    "ok": true,
                    "transcript": cleanTranscript,
                    "finalText": cleanTranscript,
                    "providerUsed": providerLabel,
                    "duration": duration,
                    "warning": "Translation error: \(error.localizedDescription)",
                ])
                return
            }
            guard let http = response as? HTTPURLResponse,
                  let data,
                  (200 ..< 300).contains(http.statusCode),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any],
                  let translated = (msg["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !translated.isEmpty
            else {
                let errText = data.flatMap { Self.parseError(from: $0) } ?? "Translation failed"
                completion([
                    "ok": true,
                    "transcript": cleanTranscript,
                    "finalText": cleanTranscript,
                    "providerUsed": providerLabel,
                    "duration": duration,
                    "warning": errText,
                ])
                return
            }

            completion([
                "ok": true,
                "transcript": cleanTranscript,
                "finalText": translated,
                "providerUsed": "\(providerLabel) → \(activeLLM.displayName)",
                "duration": duration,
            ])
        }.resume()
    }

    // MARK: - Utilities

    private static func speechLocale(for code: String) -> Locale {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "", "auto": return Locale.current
        case "vi": return Locale(identifier: "vi-VN")
        case "en": return Locale(identifier: "en-US")
        case "zh": return Locale(identifier: "zh-CN")
        case "ja": return Locale(identifier: "ja-JP")
        case "ko": return Locale(identifier: "ko-KR")
        case "fr": return Locale(identifier: "fr-FR")
        case "de": return Locale(identifier: "de-DE")
        case "es": return Locale(identifier: "es-ES")
        case "th": return Locale(identifier: "th-TH")
        default: return Locale(identifier: code)
        }
    }

    private static func languageDisplayName(_ code: String) -> String {
        switch code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "vi": return "Vietnamese"
        case "en", "en-us", "en-gb": return "English"
        case "zh", "zh-cn", "zh-tw": return "Chinese"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "fr": return "French"
        case "de": return "German"
        case "es": return "Spanish"
        case "th": return "Thai"
        case "auto": return "auto-detected language"
        default: return code
        }
    }

    private static func parseTranscriptionText(from data: Data) -> String {
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let t = dict["text"] as? String {
                return t.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let t = dict["transcript"] as? String {
                return t.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let inner = dict["data"] as? [String: Any], let t = inner["text"] as? String {
                return t.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let raw = String(data: data, encoding: .utf8) {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private static func parseError(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? nil : String(raw.prefix(200))
        }
        if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
        if let msg = obj["message"] as? String { return msg }
        if let detail = obj["detail"] as? String { return detail }
        if let errStr = obj["error"] as? String { return errStr }
        return nil
    }
}

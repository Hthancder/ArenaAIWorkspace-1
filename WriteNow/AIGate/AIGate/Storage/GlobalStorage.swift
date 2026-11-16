//
//  GlobalStorage.swift
//  MobileAffine
//
//  Created by 秋星桥 on 2024/6/28.
//

import CommonCrypto
import Foundation

private let dirname = "wiki.qaq.ai.gate"

#if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
    private let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(dirname)
#else
    private let dir = URL(fileURLWithPath: "/var/mobile/Library/Preferences/")
        .appendingPathComponent(dirname)
#endif

extension String {
    var sha1: String {
        let data = Data(utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest) }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

class GlobalStorage: PersistProvider {
    static let shared = GlobalStorage()
    private let ioQueue = DispatchQueue(label: "wiki.qaq.aigate.globalstorage")

    private init() {}

    func path(forKey: String) -> URL {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(forKey.sha1)
    }

    func data(forKey: String) -> Data? {
        ioQueue.sync {
            try? Data(contentsOf: path(forKey: forKey))
        }
    }

    func set(_ data: Data?, forKey: String) {
        ioQueue.sync {
            let url = path(forKey: forKey)
            if let data {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    func removeObject(forKey: String) {
        ioQueue.sync {
            try? FileManager.default.removeItem(at: path(forKey: forKey))
        }
    }

    var backgroundImageURL: URL {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("custom_bg.jpg")
    }

    func saveBackgroundImage(_ data: Data?) {
        ioQueue.sync {
            let url = backgroundImageURL
            if let data, !data.isEmpty {
                try? data.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func loadBackgroundImage() -> Data? {
        ioQueue.sync {
            try? Data(contentsOf: backgroundImageURL)
        }
    }

    func readDirectValue<T: Codable>(forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

extension Persist {
    init(key: String, defaultValue: Value) {
        self.init(key: key, defaultValue: defaultValue, engine: GlobalStorage.shared)
    }
}

extension PublishedPersist {
    init(key: String, defaultValue: Value) {
        self.init(key: key, defaultValue: defaultValue, engine: GlobalStorage.shared)
    }
}

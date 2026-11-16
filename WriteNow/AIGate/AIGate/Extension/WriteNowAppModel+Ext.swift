//
//  WriteNowAppModel+Ext.swift
//  AIGate
//
//  Created by Lessica on 2024/8/27.
//

import SwiftUI

final class WriteNowAppModel: ObservableObject {
    static let shared = WriteNowAppModel()
    let tweakURL = Bundle.main.url(forResource: "WriteNow", withExtension: "dylib")

    private init() {}

    @Published var isLiteEdition = false
    @Published var isJailbroken = true

    func beginBackgroundTask() {}
    func endBackgroundTask() {}
}

extension WriteNowRootView {
    func spawnService() {}
}

struct LiteEditionBannerHeader: View {
    var body: some View {
        EmptyView()
    }
}

struct LiteEditionBannerFooter: View {
    var body: some View {
        EmptyView()
    }
}

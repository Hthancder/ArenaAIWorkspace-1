//
//  WritingToolsView+Error.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

import Foundation
import SwiftUI

let kErrorCodeRetry = -101

extension WritingToolsView {
    var errorView: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.yellow)
                    Text(error?.localizedDescription ?? "")
                        .font(.footnote.weight(.medium))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: innerSpacing) {
                BeautifulButton(title: "Back".localized) {
                    error = nil
                    resetRetryFlags()
                }
                BeautifulButton(title: "Providers".localized) {
                    showQuickProviderSheet = true
                }
                BeautifulButton(title: "Again".localized) {
                    error = nil
                    resetRetryFlags()
                    executeCurrentTask()
                }
            }
            .frame(height: 36)
        }
    }
}

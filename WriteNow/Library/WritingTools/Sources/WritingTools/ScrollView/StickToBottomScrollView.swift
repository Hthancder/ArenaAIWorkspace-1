//
//  StickToBottomScrollView.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/16.
//

import Foundation
import SwiftUI
import UIKit

struct StickToBottomScrollView<T: View>: UIViewRepresentable {
    typealias UIViewType = UIStickToBottomScrollView

    @ViewBuilder
    let buildView: () -> T

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIViewType {
        let view = UIStickToBottomScrollView()
        let hostingView = UIHostingView(rootView: buildView())
        context.coordinator.hostingView = hostingView
        view.setArrangedSubview(hostingView)
        return view
    }

    func updateUIView(_ uiView: UIViewType, context: Context) {
        if let hostingView = context.coordinator.hostingView {
            hostingView.rootView = buildView()
            uiView.relayoutArrangedView(scrollIfSticky: true)
        } else {
            let hostingView = UIHostingView(rootView: buildView())
            context.coordinator.hostingView = hostingView
            uiView.setArrangedSubview(hostingView)
        }
    }

    final class Coordinator {
        var hostingView: UIHostingView<T>?
    }
}

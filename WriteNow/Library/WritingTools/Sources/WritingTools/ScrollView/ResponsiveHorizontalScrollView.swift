//
//  ResponsiveHorizontalScrollView.swift
//  WritingTools
//

import SwiftUI
import UIKit

/// A single-row horizontal scroll bar backed by UIScrollView with
/// `delaysContentTouches = false` so taps on buttons inside popovers
/// register immediately without iOS 15 SwiftUI ScrollView touch-swallowing.
struct ResponsiveHorizontalScrollView<Content: View>: UIViewRepresentable {
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIHorizontalChipScrollView {
        let scrollView = UIHorizontalChipScrollView()
        let host = UIHostingView(rootView: content())
        host.backgroundColor = .clear
        context.coordinator.hostingView = host
        scrollView.setArrangedSubview(host)
        return scrollView
    }

    func updateUIView(_ uiView: UIHorizontalChipScrollView, context: Context) {
        if let host = context.coordinator.hostingView {
            host.rootView = content()
            uiView.relayoutArrangedView()
        } else {
            let host = UIHostingView(rootView: content())
            host.backgroundColor = .clear
            context.coordinator.hostingView = host
            uiView.setArrangedSubview(host)
        }
    }

    final class Coordinator {
        var hostingView: UIHostingView<Content>?
    }
}

final class UIHorizontalChipScrollView: UIScrollView {
    weak var arrangedView: UIView?
    private var cachedHeight: CGFloat = 28

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = false
        alwaysBounceVertical = false
        isDirectionalLockEnabled = true
        delaysContentTouches = false
        canCancelContentTouches = true
        clipsToBounds = true
        contentInsetAdjustmentBehavior = .never
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesShouldCancel(in _: UIView) -> Bool {
        true
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: cachedHeight)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: cachedHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let view = arrangedView, bounds.height > 0 {
            let h = max(cachedHeight, bounds.height)
            if abs(view.frame.height - h) > 0.5 {
                view.frame.size.height = h
                contentSize.height = h
            }
        }
    }

    func setArrangedSubview(_ view: UIView) {
        if arrangedView !== view {
            arrangedView?.removeFromSuperview()
            arrangedView = view
            addSubview(view)
        }
        relayoutArrangedView()
    }

    func relayoutArrangedView() {
        guard let view = arrangedView else { return }
        view.invalidateIntrinsicContentSize()
        let fitting = view.sizeThatFits(CGSize(width: 100_000, height: 48))
        let w = max(1, ceil(fitting.width))
        let h = max(26, ceil(fitting.height))
        let targetFrame = CGRect(x: 0, y: 0, width: w, height: h)
        if view.frame != targetFrame {
            view.frame = targetFrame
        }
        let targetContentSize = CGSize(width: w, height: h)
        if contentSize != targetContentSize {
            contentSize = targetContentSize
        }
        if abs(cachedHeight - h) > 0.5 {
            cachedHeight = h
            invalidateIntrinsicContentSize()
        }
    }
}

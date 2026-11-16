//
//  UIStickToBottomScrollView.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/16.
//

import UIKit

class UIStickToBottomScrollView: UIScrollView, UIScrollViewDelegate {
    weak var arrangedView: UIView?
    private var shouldStickToBottom = true
    private var lastWidth: CGFloat = 0

    init() {
        super.init(frame: .zero)

        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = true
        indicatorStyle = .white
        contentOffset = .zero
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let distanceFromBottom = scrollView.contentSize.height - scrollView.bounds.height - scrollView.contentOffset.y
        if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
            shouldStickToBottom = distanceFromBottom <= 32
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - lastWidth) > 0.5, bounds.width > 0 {
            lastWidth = bounds.width
            relayoutArrangedView(scrollIfSticky: false)
        }
    }

    func setArrangedSubview(_ view: UIView) {
        if arrangedView !== view {
            arrangedView?.removeFromSuperview()
            arrangedView = view
            addSubview(view)
            shouldStickToBottom = true
        }
        relayoutArrangedView(scrollIfSticky: true)
    }

    func relayoutArrangedView(scrollIfSticky: Bool) {
        guard let view = arrangedView else { return }
        let targetWidth = max(bounds.width, 100)
        view.invalidateIntrinsicContentSize()
        let fittingSize = view.sizeThatFits(.init(width: targetWidth, height: .greatestFiniteMagnitude))
        let newSize = CGSize(width: targetWidth, height: fittingSize.height)
        if view.frame.size != newSize {
            view.frame = CGRect(origin: .zero, size: newSize)
        }
        if contentSize != newSize {
            contentSize = newSize
        }

        let offsetY = max(0, contentSize.height - bounds.height)
        if scrollIfSticky, shouldStickToBottom, offsetY > 0 {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.setContentOffset(.init(x: 0, y: offsetY), animated: false)
            }
        }
    }

    func resetStickyScroll() {
        shouldStickToBottom = true
    }
}

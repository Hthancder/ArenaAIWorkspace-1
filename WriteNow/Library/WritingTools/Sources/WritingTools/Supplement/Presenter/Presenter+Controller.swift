//
//  Presenter+Controller.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/18.
//

import Foundation
import SwiftUI
import UIKit

class WritingToolController: UIHostingController<WritingToolsView> {
    let context: Presenter.Context
    var basePreferredSize: CGSize = .init(width: 390, height: 390)
    var compactPreferredSize: CGSize = .init(width: 390, height: 390)
    var isExpandedSize: Bool = false
    var hostedOverlayWindow: UIWindow?

    init(context: Presenter.Context) {
        self.context = context
        super.init(rootView: .init(context: context))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setExpandedSize(_ expanded: Bool) {
        isExpandedSize = expanded
        let target: CGSize
        if expanded {
            let bounds = UIScreen.main.bounds
            let w = max(compactPreferredSize.width, min(680, bounds.width - 14))
            let h = max(compactPreferredSize.height, min(bounds.height * 0.78, 680))
            target = CGSize(width: w, height: h)
        } else {
            target = compactPreferredSize
        }
        basePreferredSize = target
        UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0.4) {
            self.preferredContentSize = target
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        let win = hostedOverlayWindow
        hostedOverlayWindow = nil
        if let win {
            DispatchQueue.main.async {
                win.isHidden = true
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        for decorationView in context.decorationViews {
            decorationView.alpha = 0
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let screenHeight = UIScreen.main.bounds.height
        let topSafe = view.window?.safeAreaInsets.top ?? 24
        let availableHeight = max(210, screenHeight - keyboardFrame.height - topSafe - 24)
        let targetHeight = min(basePreferredSize.height, availableHeight)
        if abs(preferredContentSize.height - targetHeight) > 4 {
            UIView.animate(withDuration: 0.22) {
                self.preferredContentSize = CGSize(width: self.basePreferredSize.width, height: targetHeight)
            }
        }
    }

    @objc private func keyboardWillHide(_: Notification) {
        if abs(preferredContentSize.height - basePreferredSize.height) > 4 {
            UIView.animate(withDuration: 0.22) {
                self.preferredContentSize = self.basePreferredSize
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        for view in context.decorationViews {
            view.alpha = 0
        }
        UIView.animate(withDuration: 0.25) { [self] in
            for view in context.decorationViews {
                view.alpha = 0.5
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        UIView.animate(withDuration: 0.25) { [self] in
            for view in context.decorationViews {
                view.alpha = 0
            }
        } completion: { [self] _ in
            for view in context.decorationViews {
                view.removeFromSuperview()
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        context.anchorView.removeFromSuperview()
        context.decorationViews.forEach { $0.removeFromSuperview() }
        if let overlay = hostedOverlayWindow {
            overlay.isHidden = true
            hostedOverlayWindow = nil
        }
        if Presenter.shared.activeToolController === self {
            Presenter.shared.activeToolController = nil
            Presenter.shared.activePopoverHostWindow = nil
        }
        if !context.textProxy.isReadOnly, context.targetView.window != nil {
            if let textInput = context.targetView as? UITextInput {
                textInput.selectedTextRange = context.textProxy.replacedRange
            }
            context.targetView.becomeFirstResponder()
        }
    }
}

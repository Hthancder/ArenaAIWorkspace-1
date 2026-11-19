//
//  Presenter.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/8.
//

import ColorfulX
import Foundation
import UIKit

@objc(WritingToolsPresenter)
public class Presenter: NSObject {
    @objc(sharedInstance)
    public static let shared = Presenter()

    weak var activeToolController: UIViewController?
    weak var activePopoverHostWindow: UIWindow?
    var lastPopoverPresentAt: Date = .distantPast

    override private init() {
        super.init()

        // pre-warm runtime configuration lazily without compiling Metal shaders on every app launch
        Configurator.shared.refreshRuntimeConfigIfStale(maxAge: 2.0)
    }
}

//
//  Presenter+MenuItem.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/19.
//

import Foundation
import UIKit

import WritingToolsLocalizable

extension Presenter {
    @objc(writingToolMenuName)
    func writingToolMenuName() -> String {
        WritingToolsLocalizable.shared.localizedMenuItemTitle()
    }

    @objc(isReadOnlyEnabled)
    func isReadOnlyEnabled() -> Bool {
        Configurator.shared.settings.readOnlyEnabled
    }

    @objc(shouldInjectIntoContextMenus)
    func shouldInjectIntoContextMenus() -> Bool {
        Configurator.shared.settings.injectIntoContextMenus
    }

    @objc(shouldUnlockBlockedSelection)
    func shouldUnlockBlockedSelection() -> Bool {
        Configurator.shared.settings.unlockBlockedSelection
    }

    @objc(hasExtractableTextNearView:windowPoint:)
    func hasExtractableTextNearView(_ view: UIView?, windowPoint: CGPoint) -> Bool {
        TextProxy.hasExtractableTextNearView(view, windowPoint: windowPoint)
    }

    @objc(attachScreenPickerToWindow:)
    func attachScreenPicker(to window: UIWindow) {
        ScreenPickerCoordinator.shared.attachIfNeeded(to: window)
    }

    @objc(isResponderReadOnly:)
    func isResponderReadOnly(_ responder: UIResponder) -> Bool {
        if let view = responder as? UIView,
           let voi = TextProxy.lookupViewOfInterest(view: view)
        {
            return voi._isReadOnly
        }
        if let tv = responder as? UITextView {
            return !tv.isEditable
        }
        if responder is UITextField {
            return false
        }
        return true
    }

    @objc(shouldShowMainMenuItemForReadOnly:)
    func shouldShowMainMenuItem(forReadOnly isReadOnly: Bool) -> Bool {
        let s = Configurator.shared.settings
        if isReadOnly {
            return s.readOnlyEnabled && s.showMainMenuItemInSelection && s.showMainMenuItemOnReadOnly
        }
        return s.showMainMenuItemInSelection
    }

    @objc(menuPresentationMode)
    func menuPresentationMode() -> String {
        Configurator.shared.settings.selectionMenuPresentationMode
    }

    func activeSelectionMenuSlots(isReadOnly: Bool) -> [(slotIndex: Int, item: RuntimeSelectionMenuItem)] {
        let s = Configurator.shared.settings
        if isReadOnly && !s.readOnlyEnabled {
            return []
        }
        let filtered = s.selectionMenuItems.filter { item in
            guard item.isEnabled else { return false }
            let cleanTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty else { return false }
            return item.availability.matches(
                isReadOnly: isReadOnly,
                showEditableInReadOnly: s.readOnlyShowEditablePresets
            )
        }
        return filtered.prefix(12).enumerated().map { idx, item in
            (slotIndex: idx + 1, item: item)
        }
    }

    func resolveLaunchItem(slotIndex: Int, isReadOnly: Bool) -> RuntimeSelectionMenuItem? {
        guard slotIndex >= 1 else { return nil }
        return activeSelectionMenuSlots(isReadOnly: isReadOnly)
            .first(where: { $0.slotIndex == slotIndex })?
            .item
    }

    @objc(canPerformCustomSlot:isReadOnly:)
    func canPerformCustomSlot(_ slotIndex: Int, isReadOnly: Bool) -> Bool {
        if slotIndex == 0 {
            return shouldShowMainMenuItem(forReadOnly: isReadOnly)
        }
        return activeSelectionMenuSlots(isReadOnly: isReadOnly).contains { $0.slotIndex == slotIndex }
    }

    @objc(customSelectionMenuItemsForReadOnly:)
    func customSelectionMenuItems(forReadOnly isReadOnly: Bool) -> [[String: Any]] {
        Configurator.shared.refreshRuntimeConfigIfStale(maxAge: 2.5)
        return activeSelectionMenuSlots(isReadOnly: isReadOnly).map { slot in
            [
                "slotIndex": slot.slotIndex,
                "title": slot.item.title,
                "icon": slot.item.icon,
                "selector": "_WT_CustomSlot_\(slot.slotIndex)_3cf98861",
            ]
        }
    }
}

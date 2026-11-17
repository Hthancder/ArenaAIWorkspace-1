//
//  TextProxy+VOI.swift
//  WritingTools
//
//  Created by 秋星桥 on 2024/8/20.
//

import UIKit

extension TextProxy {
    static func lookupViewOfInterest(view: UIView) -> TextProxyObject? {
        if let hit = lookupDescendantViewOfInterest(view: view) {
            return hit
        }
        var cursor: UIView? = view.superview
        for _ in 0 ..< 4 {
            guard let candidate = cursor else { break }
            if let proxyObj = candidate as? TextProxyObject, proxyObj._eligibleForWritingTool {
                return proxyObj
            }
            cursor = candidate.superview
        }
        return nil
    }

    private static func lookupDescendantViewOfInterest(view: UIView) -> TextProxyObject? {
        if let view = view as? TextProxyObject, view._eligibleForWritingTool {
            return view
        }
        for subview in view.subviews {
            if let found = lookupDescendantViewOfInterest(view: subview) {
                return found
            }
        }
        return nil
    }
}

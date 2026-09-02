//
//  UIView+HiddenOnCapture.swift
//

import UIKit

public extension UIView {

    /// Hides this view, and everything inside it, from screenshots, recordings and
    /// mirrored streams.
    func makeHiddenOnCapture() {
        layer.makeHiddenOnCapture()
        CaptureMonitor.shared.hideWhileCapturing(self)
    }
}

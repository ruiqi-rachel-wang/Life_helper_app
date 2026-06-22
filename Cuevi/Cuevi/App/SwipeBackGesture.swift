//  SwipeBackGesture.swift
//
//  Our screens hide the system navigation bar (`.navigationBarHidden(true)`) and draw
//  their own back chevrons. Hiding the bar normally disables iOS's edge-swipe "back"
//  gesture, which feels broken. This re-enables that gesture app-wide: keep the
//  interactive pop working whenever there's a previous screen to return to.
//

import UIKit

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only allow the swipe when there is something to pop back to (not the root).
        viewControllers.count > 1
    }
}

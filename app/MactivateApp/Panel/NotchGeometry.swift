import AppKit
import CoreGraphics

struct ScreenDescriptor: Equatable {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaTop: CGFloat
    let auxiliaryTopLeftArea: CGRect?
    let auxiliaryTopRightArea: CGRect?
    let isBuiltIn: Bool

    var hasNotch: Bool {
        safeAreaTop > 0 &&
            auxiliaryTopLeftArea != nil &&
            auxiliaryTopRightArea != nil
    }
}

enum NotchGeometry {
    static let screenEdgePadding: CGFloat = 8

    static func panelFrame(
        on screen: ScreenDescriptor,
        panelSize: CGSize
    ) -> CGRect {
        let anchorX: CGFloat
        let top: CGFloat

        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           screen.hasNotch {
            anchorX = (left.maxX + right.minX) / 2
            top = screen.frame.maxY - screen.safeAreaTop
        } else {
            anchorX = screen.frame.midX
            top = screen.visibleFrame.maxY
        }

        let proposedX = anchorX - panelSize.width / 2
        let minimumX = screen.frame.minX + screenEdgePadding
        let maximumX = screen.frame.maxX - panelSize.width - screenEdgePadding
        let x = min(max(proposedX, minimumX), max(minimumX, maximumX))

        return CGRect(
            x: x,
            y: top - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}

extension NSScreen {
    var mactivateDescriptor: ScreenDescriptor? {
        guard let number = deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        return ScreenDescriptor(
            displayID: displayID,
            frame: frame,
            visibleFrame: visibleFrame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeftArea: auxiliaryTopLeftArea,
            auxiliaryTopRightArea: auxiliaryTopRightArea,
            isBuiltIn: CGDisplayIsBuiltin(displayID) != 0
        )
    }
}

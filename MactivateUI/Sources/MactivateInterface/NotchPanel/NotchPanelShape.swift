#if os(macOS)
import SwiftUI
import MactivateDesign

/// The panel's silhouette: square at the top edge where it meets the bezel,
/// rounded at the bottom, with small inward curves ("shoulders") either side of
/// the notch.
///
/// Those shoulders are the whole illusion. Without them the surface is a floating
/// card that happens to be near the notch; with them the hardware cut-out and the
/// software panel read as one object, which is what makes the drop-down feel like
/// it belongs to the Mac rather than to an app.
struct NotchPanelShape: Shape {
    /// Notch width in the panel's own coordinate space.
    var notchWidth: CGFloat
    /// Notch height; the shoulders curve over this distance.
    var notchHeight: CGFloat
    var cornerRadius: CGFloat
    /// When false (a display without a notch) the shape is a plain rounded card.
    var isNotchAttached: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard isNotchAttached, notchWidth > 0 else {
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
                style: .continuous
            )
            return path
        }

        let shoulder = min(notchHeight, 12)
        let notchLeft = rect.midX - notchWidth / 2
        let notchRight = rect.midX + notchWidth / 2

        // Start just left of the notch at the top edge and run anticlockwise.
        path.move(to: CGPoint(x: max(rect.minX, notchLeft - shoulder), y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: notchLeft, y: rect.minY + shoulder),
            control: CGPoint(x: notchLeft, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: notchLeft, y: rect.minY + notchHeight))
        path.addLine(to: CGPoint(x: notchRight, y: rect.minY + notchHeight))
        path.addLine(to: CGPoint(x: notchRight, y: rect.minY + shoulder))
        path.addQuadCurve(
            to: CGPoint(x: min(rect.maxX, notchRight + shoulder), y: rect.minY),
            control: CGPoint(x: notchRight, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

/// The panel's background: system material, a hairline edge, and a soft shadow.
///
/// Material rather than a solid colour so the panel inherits Dark Mode, wallpaper
/// tinting, and the reduce-transparency setting the way system surfaces do.
struct NotchPanelBackground: View {
    let layout: NotchPanelLayout

    var body: some View {
        let shape = NotchPanelShape(
            notchWidth: layout.notch.width,
            notchHeight: layout.notch.height,
            cornerRadius: layout.cornerRadius,
            isNotchAttached: layout.isNotchAttached
        )

        shape
            .fill(.regularMaterial)
            .overlay(shape.stroke(Theme.separator.opacity(0.8), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 22, y: 8)
    }
}
#endif

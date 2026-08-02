import Foundation

/// Geometry for the device map: the top-down MacBook-on-a-desk illustration that
/// every region-picking surface draws. The numbers live here, once, in a 0…1
/// space so the same layout scales from the notch panel's inline map to the
/// full-window calibration map without drifting apart.
public enum DeviceMapLayout {
    /// The MacBook's lower half (keyboard deck and palm rests) as drawn.
    public static let deck = NormalizedRect(x: 0.17, y: 0.24, width: 0.66, height: 0.60)
    /// The screen/lid hint drawn above the deck, including the notch nub.
    public static let lid = NormalizedRect(x: 0.20, y: 0.05, width: 0.60, height: 0.17)
    /// The palm-rest strip inside the deck, where palm regions are drawn.
    public static let palmStrip = NormalizedRect(x: 0.17, y: 0.62, width: 0.66, height: 0.22)
    /// The trackpad, drawn for orientation only. It is never a tap region: a
    /// trackpad tap is a click, and separating the two is a false-positive
    /// problem we refuse to create.
    public static let trackpad = NormalizedRect(x: 0.42, y: 0.64, width: 0.16, height: 0.15)

    public static let palmLeft = NormalizedRect(x: 0.185, y: 0.635, width: 0.215, height: 0.185)
    public static let palmCenter = NormalizedRect(x: 0.415, y: 0.635, width: 0.170, height: 0.185)
    public static let palmRight = NormalizedRect(x: 0.600, y: 0.635, width: 0.215, height: 0.185)
    public static let palmWhole = NormalizedRect(x: 0.185, y: 0.635, width: 0.630, height: 0.185)

    public static let deskLeft = NormalizedRect(x: 0.020, y: 0.34, width: 0.125, height: 0.44)
    public static let deskRight = NormalizedRect(x: 0.855, y: 0.34, width: 0.125, height: 0.44)
    public static let deskFront = NormalizedRect(x: 0.240, y: 0.875, width: 0.520, height: 0.100)
    public static let deskWhole = NormalizedRect(x: 0.020, y: 0.875, width: 0.960, height: 0.100)

    public static func frame(surface: TapSurface, zone: TapZone) -> NormalizedRect {
        switch (surface, zone) {
        case (.palmRest, .left): return palmLeft
        case (.palmRest, .center): return palmCenter
        case (.palmRest, .right): return palmRight
        case (.palmRest, .whole): return palmWhole
        case (.desk, .left): return deskLeft
        case (.desk, .right): return deskRight
        case (.desk, .center): return deskFront
        case (.desk, .whole): return deskWhole
        }
    }
}

public enum DefaultConfiguration {
    /// The regions offered before calibration has told us what this machine can
    /// actually localize. Every one starts `.uncalibrated`: the product rule is
    /// that capability discovery precedes calibration precedes mapping, so the
    /// UI must never present a region as working because it exists in a default.
    public static func regions() -> [TapRegion] {
        [
            TapRegion(surface: .palmRest, zone: .left, frame: DeviceMapLayout.palmLeft),
            TapRegion(surface: .palmRest, zone: .center, frame: DeviceMapLayout.palmCenter),
            TapRegion(surface: .palmRest, zone: .right, frame: DeviceMapLayout.palmRight),
            TapRegion(surface: .desk, zone: .left, frame: DeviceMapLayout.deskLeft),
            TapRegion(surface: .desk, zone: .center, frame: DeviceMapLayout.deskFront),
            TapRegion(surface: .desk, zone: .right, frame: DeviceMapLayout.deskRight)
        ]
    }

    /// The single-region fallback used when region localization is refuted on
    /// this machine: one palm-rest region and one desk region.
    public static func collapsedRegions(reason: String) -> [TapRegion] {
        [
            TapRegion(surface: .palmRest, zone: .whole, frame: DeviceMapLayout.palmWhole),
            TapRegion(
                surface: .desk,
                zone: .whole,
                frame: DeviceMapLayout.deskWhole,
                calibration: .unsupported(reason: reason)
            )
        ]
    }

    /// A blank configuration: real regions, no bindings, an empty pad page.
    /// Deliberately empty rather than pre-bound — a shortcut the user did not
    /// choose firing from a tap they did not expect is the worst first run.
    public static func empty() -> MactivateConfiguration {
        MactivateConfiguration(
            regions: regions(),
            bindings: [],
            macroPad: MacroPad(pages: [
                MacroPadPage(
                    title: "Pad 1",
                    symbolName: "square.grid.2x2",
                    slots: MacroPad.normalizedSlots([])
                )
            ])
        )
    }
}

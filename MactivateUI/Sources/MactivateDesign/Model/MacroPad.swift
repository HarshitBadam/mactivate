import Foundation

/// One macro-pad button. The pad is the part of the panel you *click*: it runs
/// its action immediately, so it works on machines where tap sensing is
/// unavailable and gives every action a discoverable home before it is bound to
/// a tap.
public struct MacroPadSlot: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    /// Empty slots are drawn as dashed "Add Action" placeholders rather than
    /// being absent, so the grid keeps a stable shape while editing.
    public var action: ActionSpec?
    /// Overrides the action's own title when the user wants a shorter cap label.
    public var label: String?

    public init(id: UUID = UUID(), action: ActionSpec? = nil, label: String? = nil) {
        self.id = id
        self.action = action
        self.label = label
    }

    public var isEmpty: Bool { action == nil }

    public var displayLabel: String {
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty { return label }
        return action?.title ?? "Add Action"
    }

    public var symbolName: String { action?.symbolName ?? "plus" }
}

/// A page of macro-pad buttons. Pages keep the notch panel from becoming a wall
/// of buttons; the panel shows one page at a time with a segmented control.
public struct MacroPadPage: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var symbolName: String
    public var slots: [MacroPadSlot]

    public init(id: UUID = UUID(), title: String, symbolName: String = "square.grid.2x2", slots: [MacroPadSlot]) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.slots = slots
    }
}

public struct MacroPad: Equatable, Codable, Sendable {
    /// Buttons per row in the pad grid. Four reads as a pad rather than a list
    /// at the notch panel's width and stays inside the grid's minimum cap size.
    public static let columns = 4
    /// Rows per page. Two rows of four keeps a page glanceable.
    public static let rowsPerPage = 2
    public static var slotsPerPage: Int { columns * rowsPerPage }

    public var pages: [MacroPadPage]

    public init(pages: [MacroPadPage]) {
        self.pages = pages
    }

    public var isEmpty: Bool { pages.allSatisfy { $0.slots.allSatisfy(\.isEmpty) } }

    public func page(_ id: UUID) -> MacroPadPage? { pages.first { $0.id == id } }

    /// Pads a page out to a full grid so the layout never reflows as the user
    /// fills it in.
    public static func normalizedSlots(_ slots: [MacroPadSlot]) -> [MacroPadSlot] {
        var result = Array(slots.prefix(slotsPerPage))
        while result.count < slotsPerPage { result.append(MacroPadSlot()) }
        return result
    }
}

import Foundation

/// Finder-like selection for the side-panel grid: click selects one item,
/// ⌘-click toggles, ⇧-click selects the range from the last plain click.
/// Without the keyboard: a drag that starts on an unselected item selects the
/// range from it to the item under the pointer; one that starts on a selected
/// item drags the whole selection into another app (see `dragSelects`).
public struct GridSelection<Item: Hashable> {
    public var selected: Set<Item>
    public var anchor: Item?

    public init(selected: Set<Item> = [], anchor: Item? = nil) {
        self.selected = selected
        self.anchor = anchor
    }

    public mutating func click(_ item: Item, in order: [Item], command: Bool, shift: Bool) {
        if shift, let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: item) {
            selected = Set(order[min(from, to)...max(from, to)])
        } else if command {
            if selected.remove(item) == nil { selected.insert(item) }
            anchor = item
        } else {
            selected = [item]
            anchor = item
        }
    }

    /// Whether a drag from `item` selects (true) or carries the selection
    /// out of the app (false).
    public func dragSelects(from item: Item) -> Bool { !selected.contains(item) }

    /// A selecting drag from `start` that is now over `current`: the range
    /// between them, in grid order, replaces the selection, as ⇧-click does.
    public mutating func drag(from start: Item, to current: Item, in order: [Item]) {
        guard let from = order.firstIndex(of: start), let to = order.firstIndex(of: current) else { return }
        selected = Set(order[min(from, to)...max(from, to)])
        anchor = start
    }

    /// A right-click on a selected item acts on the whole selection, on any
    /// other item only on that one.
    public func targets(forContextClickOn item: Item, in order: [Item]) -> [Item] {
        selected.contains(item) ? order.filter(selected.contains) : [item]
    }

    /// What Space shows in Quick Look, as in Finder: one selected item opens
    /// the whole grid there (arrows move on), several show only those. Starts
    /// at the last clicked item. Nil when nothing in `order` is selected.
    public func previewItems(in order: [Item]) -> (items: [Item], start: Int)? {
        let chosen = order.filter(selected.contains)
        guard let first = chosen.first else { return nil }
        let items = chosen.count == 1 ? order : chosen
        let current = anchor.flatMap { selected.contains($0) ? $0 : nil } ?? first
        return (items, items.firstIndex(of: current) ?? 0)
    }
}

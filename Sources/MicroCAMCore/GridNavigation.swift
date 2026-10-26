import CoreGraphics

/// Arrow keys in the side-panel grid, as in Finder.
public enum GridMove: Equatable, Sendable {
    case left, right, up, down
}

/// Which tile an arrow key moves the selection to. ← / → go to the previous
/// or next capture in grid order (across rows and days); ↑ / ↓ to the tile in
/// the row above or below nearest to the current one's centre, from the
/// frames of the tiles on screen. The grid is lazy, so for a row that isn't
/// laid out it counts rows of the current row's width within each day
/// (`sections`; each day starts a new row), to the same column, or the last
/// tile of a shorter row. Nil at an edge: the selection stays.
public enum GridNavigation {
    public static func target<Item: Hashable>(from current: Item?, move: GridMove, order: [Item],
                                              frames: [Item: CGRect], sections: [[Item]]? = nil) -> Item? {
        guard let current, let index = order.firstIndex(of: current) else { return order.first }
        switch move {
        case .left: return index > 0 ? order[index - 1] : nil
        case .right: return index + 1 < order.count ? order[index + 1] : nil
        case .up, .down:
            let down = move == .down
            if let here = frames[current] {
                let rows = frames.filter { down ? $0.value.minY > here.minY + 1 : $0.value.minY < here.minY - 1 }
                if let rowY = down ? rows.map(\.value.minY).min() : rows.map(\.value.minY).max() {
                    return rows.filter { abs($0.value.minY - rowY) < 1 }
                        .min { abs($0.value.midX - here.midX) < abs($1.value.midX - here.midX) }?.key
                }
            }
            // The widest row on screen: the current one may be a day's shorter last row.
            let columns = max(1, Dictionary(grouping: frames.values) { ($0.minY).rounded() }.values.map(\.count).max() ?? 1)
            return rowNeighbour(of: current, down: down, columns: columns, sections: sections ?? [order])
        }
    }

    /// The same column one row down or up, counting rows within each section.
    private static func rowNeighbour<Item: Hashable>(of item: Item, down: Bool, columns: Int, sections: [[Item]]) -> Item? {
        guard let s = sections.firstIndex(where: { $0.contains(item) }), let p = sections[s].firstIndex(of: item) else { return nil }
        let column = p % columns, row = p / columns
        func pick(_ section: [Item], row: Int) -> Item? {
            let start = row * columns
            return section.indices.contains(start) ? section[min(start + column, section.count - 1)] : nil
        }
        if down {
            if let below = pick(sections[s], row: row + 1) { return below }
            return sections[(s + 1)...].first { !$0.isEmpty }.flatMap { pick($0, row: 0) }
        }
        if row > 0 { return pick(sections[s], row: row - 1) }
        return sections[..<s].last { !$0.isEmpty }.flatMap { pick($0, row: ($0.count - 1) / columns) }
    }
}

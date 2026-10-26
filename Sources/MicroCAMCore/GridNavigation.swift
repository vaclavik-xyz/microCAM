import CoreGraphics

/// Arrow keys in the side-panel grid, as in Finder.
public enum GridMove: Equatable, Sendable {
    case left, right, up, down
}

/// Which tile an arrow key moves the selection to. ← / → go to the previous
/// or next capture in grid order (across rows and days); ↑ / ↓ to the tile in
/// the row above or below nearest to the current one's centre, from the
/// frames of the tiles on screen. The grid is lazy, so a row that isn't laid
/// out falls back to as many captures back or on as the current row is wide.
/// Nil at an edge: the selection stays.
public enum GridNavigation {
    public static func target<Item: Hashable>(from current: Item?, move: GridMove, order: [Item],
                                              frames: [Item: CGRect]) -> Item? {
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
            let columns = max(1, frames[current].map { here in frames.values.filter { abs($0.minY - here.minY) < 1 }.count } ?? 1)
            let next = index + (down ? columns : -columns)
            return order.indices.contains(next) ? order[next] : nil
        }
    }
}

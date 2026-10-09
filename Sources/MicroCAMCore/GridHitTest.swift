import CoreGraphics

/// Which grid tile the pointer is over during a drag, from the tiles' frames.
/// In the gap between two tiles of a row, or past the last one, the nearest
/// tile of that row counts, so a drag across a row never flickers; between
/// rows (and over a day header) there is no tile.
public enum GridHitTest {
    public static func item<Item>(at point: CGPoint, frames: [Item: CGRect]) -> Item? {
        if let hit = frames.first(where: { $0.value.contains(point) }) { return hit.key }
        return frames
            .filter { point.y >= $0.value.minY && point.y <= $0.value.maxY }
            .min { distance(point.x, $0.value) < distance(point.x, $1.value) }?
            .key
    }

    private static func distance(_ x: CGFloat, _ frame: CGRect) -> CGFloat {
        x < frame.minX ? frame.minX - x : x > frame.maxX ? x - frame.maxX : 0
    }
}

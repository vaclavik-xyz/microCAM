/// When cameras appear or disappear, should the app (re)select a camera?
/// After the working camera is unplugged the app waits for that camera to
/// come back instead of silently switching to e.g. the built-in FaceTime
/// camera, and it reselects automatically once it returns.
public enum CameraReselectPolicy {
    public static func shouldSelect(currentID: String?, rememberedID: String?, available: [String]) -> Bool {
        guard currentID == nil, !available.isEmpty else { return false }
        guard let rememberedID else { return true }
        return available.contains(rememberedID)
    }
}

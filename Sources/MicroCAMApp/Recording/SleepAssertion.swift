import IOKit.pwr_mgt

/// Prevents idle system sleep while alive. Lid close / explicit sleep still
/// sleeps; the recorder is finalized on `willSleep` in that case.
final class SleepAssertion {
    private var id: IOPMAssertionID = 0
    private let active: Bool

    init(reason: String) {
        active = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             reason as CFString, &id) == kIOReturnSuccess
    }

    deinit {
        if active { IOPMAssertionRelease(id) }
    }
}

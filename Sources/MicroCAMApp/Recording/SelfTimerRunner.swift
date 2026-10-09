import Foundation
import MicroCAMCore

/// One self-timer countdown at a time: `remaining` drives the number over the
/// picture, `onTick` the beeps, `onFire` the photo.
@MainActor
final class SelfTimerRunner: ObservableObject {
    /// Seconds left while counting down, nil otherwise.
    @Published private(set) var remaining: Int?

    var isRunning: Bool { remaining != nil }

    private var countdown: SelfTimerCountdown?
    private var timer: Timer?
    private var onTick: ((Int) -> Void)?
    private var onFire: (() -> Void)?

    /// `onTick` gets each second still to go (`seconds` … 1); `onFire` runs
    /// once when the time is up, not after `cancel()`.
    func start(seconds: Int, onTick: @escaping (Int) -> Void, onFire: @escaping () -> Void) {
        cancel()
        countdown = SelfTimerCountdown(seconds: seconds, startedAt: Date())
        self.onTick = onTick
        self.onFire = onFire
        tick()
        guard isRunning else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        countdown = nil
        onTick = nil
        onFire = nil
        remaining = nil
    }

    private func tick() {
        guard let countdown else { return }
        let left = countdown.remaining(at: Date())
        guard left > 0 else {
            let fire = onFire
            cancel()
            fire?()
            return
        }
        remaining = left
        onTick?(left)
    }
}

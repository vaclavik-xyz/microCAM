import Foundation
import MicroCAMCore

@MainActor
final class TimelapseRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var shotsTaken = 0
    @Published private(set) var schedule: TimelapseSchedule?

    var onShot: (() -> Void)?
    var onFinish: (() -> Void)?
    private var timer: Timer?

    func start(_ schedule: TimelapseSchedule) {
        stop()
        self.schedule = schedule
        shotsTaken = 0
        isRunning = true
        fire()
        guard isRunning else { return }
        let timer = Timer(timeInterval: schedule.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        timer.tolerance = min(1, schedule.interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        guard isRunning else { return }
        isRunning = false
        onFinish?()
    }

    private func fire() {
        guard isRunning, let schedule else { return }
        onShot?()
        shotsTaken += 1
        if schedule.isFinished(shotsTaken: shotsTaken) { stop() }
    }
}

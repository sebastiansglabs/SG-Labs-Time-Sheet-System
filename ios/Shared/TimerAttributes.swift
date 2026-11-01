import ActivityKit
import Foundation

/// What the lock screen / Dynamic Island timer needs to draw itself.
struct TimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// The start time pushed forward by all breaks, so "now − countFrom" is the time worked.
        /// The system counts this up on its own, even while the app is closed.
        var countFrom: Date
        /// While paused: the frozen time worked, in seconds. nil while running.
        var pausedElapsed: TimeInterval?

        var isPaused: Bool { pausedElapsed != nil }
    }

    var projectName: String
    var colorHex: String
}

/// "01:23:45"
func clockString(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
}

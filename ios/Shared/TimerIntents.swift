import AppIntents
import Foundation

// Buttons on the lock screen and in the Dynamic Island.
// The system runs a LiveActivityIntent inside the app's process (launching it in the
// background if needed), so the real work happens in the app's Store. The widget
// extension only needs these types to draw the buttons.

struct TogglePauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Timer"

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await Store.shared.togglePause()
        #endif
        return .result()
    }
}

struct StopTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Timer"

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await Store.shared.stop(fromLockScreen: true)
        #endif
        return .result()
    }
}

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private let stopRed = Color(hex: "#E5484D")

/// The running timer on the lock screen and in the Dynamic Island.
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let color = Color(hex: context.attributes.colorHex)
            return DynamicIsland {
                // Shown when the island is pressed and held
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 10, height: 10)
                        Text(context.attributes.projectName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.leading, 6)
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(state: context.state)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.trailing)
                        .padding(.trailing, 6)
                        .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ControlButtons(state: context.state)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .foregroundStyle(color)
            } compactTrailing: {
                TimerText(state: context.state)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .foregroundStyle(color)
            }
            .keylineTint(color)
        }
    }
}

/// Counts up on its own while running; frozen while paused.
struct TimerText: View {
    let state: TimerAttributes.ContentState

    var body: some View {
        Group {
            if let paused = state.pausedElapsed {
                Text(clockString(paused))
            } else {
                Text(state.countFrom, style: .timer)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(state.isPaused ? Color.white.opacity(0.6) : Color.white)
    }
}

struct ControlButtons: View {
    let state: TimerAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: TogglePauseIntent()) {
                Label(state.isPaused ? "Resume" : "Pause", systemImage: state.isPaused ? "play.fill" : "pause.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)

            Button(intent: StopTimerIntent()) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(stopRed, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }
}

struct LockScreenView: View {
    let attributes: TimerAttributes
    let state: TimerAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: attributes.colorHex)).frame(width: 10, height: 10)
                Text(attributes.projectName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(state.isPaused ? "Paused" : "Working")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            TimerText(state: state)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
            ControlButtons(state: state)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

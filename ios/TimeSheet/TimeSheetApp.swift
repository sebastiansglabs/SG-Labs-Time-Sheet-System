import SwiftUI

@main
struct TimeSheetApp: App {
    @ObservedObject private var store = Store.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .onChange(of: phase) { _, newPhase in
                    if newPhase == .active { store.becameActive() }
                }
        }
    }
}

struct RootView: View {
    @ObservedObject private var store = Store.shared
    @State private var path: [String] = [] // open project ids

    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .navigationDestination(for: String.self) { id in
                    ProjectView(projectId: id)
                }
        }
        .tint(Theme.ink)
        .safeAreaInset(edge: .bottom) {
            Dock(currentProjectId: path.last)
        }
        .fullScreenCover(isPresented: $store.timerOpen) {
            TimerScreen { entry in
                // Show the new entry where it landed
                path = [entry.projectId]
            }
        }
        .onAppear {
            // Reopening the app mid-session goes straight back to the timer
            if store.db.active != nil { store.timerOpen = true }
        }
    }
}

/// Bottom button: "Start timer", or the live time when a timer is running.
struct Dock: View {
    @ObservedObject private var store = Store.shared
    let currentProjectId: String?

    var body: some View {
        Button {
            store.openTimer(preferring: currentProjectId)
        } label: {
            if let a = store.db.active {
                let name = store.project(a.projectId)?.name ?? "Timer"
                if a.end != nil {
                    Text("Finish entry · \(name)").lineLimit(1)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(store.isPaused ? Color(hex: "#F5B942") : Color(hex: "#FF5A5F"))
                                .frame(width: 9, height: 9)
                            Text(clockString(store.elapsed() / 1000)).monospacedDigit()
                            Text("· \(name)").lineLimit(1)
                        }
                    }
                }
            } else {
                Text("Start timer")
            }
        }
        .buttonStyle(PillButtonStyle(fill: Theme.ink))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(
            LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
    }
}

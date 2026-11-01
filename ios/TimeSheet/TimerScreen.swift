import SwiftUI

/// Full-screen timer.
/// Before Start: current time, project, description, Start.
/// Running: only the timer with Pause and Stop.
/// After Stop: summary, description, photos, Save / Resume / Discard.
struct TimerScreen: View {
    @ObservedObject private var store = Store.shared
    var onSaved: (Entry) -> Void

    @State private var projectSheet: SheetProject?
    @State private var confirmStop = false
    @State private var confirmDiscard = false
    @State private var shakeChips = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bg.ignoresSafeArea()

            Group {
                if let a = store.db.active, a.end != nil {
                    finishView(a)
                } else if store.db.active != nil {
                    runningView
                } else {
                    idleView
                }
            }
            .transition(.opacity)

            Button {
                store.timerOpen = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.border))
            }
            .padding(.leading, 18)
            .padding(.top, 8)
            .accessibilityLabel("Close timer")
        }
        .animation(.easeInOut(duration: 0.3), value: store.db.active?.end != nil)
        .animation(.easeInOut(duration: 0.3), value: store.db.active == nil)
        .sheet(item: $projectSheet) { item in
            ProjectSheet(existing: item.project, onSaved: { saved in
                store.draftProjectId = saved.id
            })
        }
    }

    // MARK: Before Start

    private var idleView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ClockHeader().padding(.top, 56).padding(.bottom, 10)

                    Text("Project").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                    FlowLayout(spacing: 8) {
                        ForEach(store.db.projects) { p in
                            Button {
                                store.draftProjectId = p.id
                            } label: {
                                ProjectChip(project: p, selected: store.draftProjectId == p.id)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            projectSheet = SheetProject(project: nil)
                        } label: {
                            Text("+ New project")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 16)
                                .frame(height: 40)
                                .overlay(Capsule().stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        }
                        .buttonStyle(.plain)
                    }
                    .offset(x: shakeChips ? -6 : 0)

                    Text("Description").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                    TextField("What are you working on?", text: $store.draftDescription, axis: .vertical)
                        .lineLimit(2...6)
                        .fieldStyle()
                }
                .padding(.horizontal, 18)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 4) {
                Text("00:00:00")
                    .font(.system(size: 58, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.idleDigits)
                Text(store.db.projects.isEmpty ? "Create a project to get started" : "Pick a project, then tap Start")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .padding(.bottom, 14)
                Button("Start") {
                    guard store.project(store.draftProjectId) != nil else {
                        withAnimation(.spring(response: 0.15, dampingFraction: 0.2)) { shakeChips.toggle() }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { shakeChips = false }
                        return
                    }
                    Task { await store.start() }
                }
                .buttonStyle(PillButtonStyle(fill: Theme.go))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }

    // MARK: Running — just the timer, Pause and Stop

    private var runningView: some View {
        VStack(spacing: 28) {
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(clockString(store.elapsed() / 1000))
                    .font(.system(size: 96, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(store.isPaused ? Theme.muted : Theme.ink)
            }
            HStack(spacing: 10) {
                Button(store.isPaused ? "Resume" : "Pause") {
                    Task { await store.togglePause() }
                }
                .buttonStyle(PillButtonStyle(fill: Theme.card, ink: Theme.ink, outlined: true))

                Button("Stop") { confirmStop = true }
                    .buttonStyle(PillButtonStyle(fill: Theme.danger))
            }
            .frame(maxWidth: 420)
            Spacer()
            Spacer().frame(height: 40)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .alert("Stop the timer?", isPresented: $confirmStop) {
            Button("Cancel", role: .cancel) {}
            Button("Stop", role: .destructive) { Task { await store.stop() } }
        } message: {
            Text("You've worked \(dur(store.elapsed())) so far.")
        }
    }

    // MARK: After Stop

    private func finishView(_ a: ActiveTimer) -> some View {
        let p = store.project(a.projectId)
        let worked = store.elapsed()
        let breaks = breakTotal(a.breaks, until: a.end ?? nowMs())
        let description = Binding<String>(
            get: { store.db.active?.description ?? "" },
            set: { store.db.active?.description = $0 }
        )
        let photos = Binding<[String]>(
            get: { store.db.active?.photos ?? [] },
            set: { store.db.active?.photos = $0 }
        )

        return ScrollView {
            VStack(spacing: 14) {
                ClockHeader().padding(.top, 56).padding(.bottom, 4)

                VStack(spacing: 4) {
                    if let p {
                        HStack(spacing: 8) {
                            ProjectDot(hex: p.color, size: 24)
                            Text(p.name).font(.system(size: 14, weight: .semibold))
                        }
                    }
                    Text(worked < 60_000 ? "\(Int(worked / 1000))s" : dur(worked))
                        .font(.system(size: 46, weight: .semibold))
                        .monospacedDigit()
                        .padding(.top, 6)
                    HStack(spacing: 6) {
                        Text(timeText(a.start))
                        Text("→").foregroundStyle(Theme.muted)
                        Text(timeText(a.end ?? nowMs()))
                    }
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    if breaks >= 60_000 {
                        Text("\(dur(breaks)) break not counted").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .card()

                TextField("Description (optional)", text: description, axis: .vertical)
                    .lineLimit(1...6)
                    .fieldStyle()

                VStack(spacing: 2) {
                    Text("Add proof of work?").font(.system(size: 18, weight: .semibold))
                    Text("Snap a photo of what you worked on. It's optional.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 6)

                PhotoEditor(ids: photos, onRemove: { id in store.deletePhotos([id]) })

                VStack(spacing: 10) {
                    Button(a.photos.isEmpty ? "Skip photo & save" : "Save to log") {
                        if let entry = store.saveActive() {
                            store.timerOpen = false
                            onSaved(entry)
                        }
                    }
                    .buttonStyle(PillButtonStyle(fill: Theme.ink))

                    Button("Resume timer") { Task { await store.resume() } }
                        .buttonStyle(PillButtonStyle(fill: Theme.card, ink: Theme.ink, outlined: true))

                    Button("Discard this session") { confirmDiscard = true }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.danger)
                        .frame(height: 44)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .alert("Discard this session?", isPresented: $confirmDiscard) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) {
                Task {
                    await store.discardActive()
                    store.timerOpen = false
                }
            }
        } message: {
            Text("This session won't be saved to the log.\(a.photos.isEmpty ? "" : " Its photos are deleted too.")")
        }
    }
}

/// Big live clock and date at the top of the timer screen.
struct ClockHeader: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 2) {
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 54, weight: .semibold))
                    .monospacedDigit()
                Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

import SwiftUI

struct SheetEntry: Identifiable {
    let id = UUID()
    var entry: Entry?
}

struct ViewerItem: Identifiable {
    let id = UUID()
    let ids: [String]
    let index: Int
}

/// One project's work log: pick a month, see each day and each session.
struct ProjectView: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    let projectId: String

    @State private var month = Month.current
    @State private var projectSheet: SheetProject?
    @State private var entrySheet: SheetEntry?
    @State private var viewer: ViewerItem?

    var body: some View {
        Group {
            if let p = store.project(projectId) {
                content(p)
            } else {
                Text("This project was deleted.").foregroundStyle(Theme.muted)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $projectSheet) { item in
            ProjectSheet(existing: item.project, onDeleted: { dismiss() })
        }
        .sheet(item: $entrySheet) { item in
            EntrySheet(existing: item.entry, defaultProjectId: projectId)
        }
        .fullScreenCover(item: $viewer) { item in
            PhotoViewer(ids: item.ids, start: item.index)
        }
    }

    private func content(_ p: Project) -> some View {
        let list = store.entries(of: p.id, in: month)
        let total = list.reduce(0) { $0 + $1.worked }
        let hours = billedHours(total)
        let byDay = Dictionary(grouping: list) { Calendar.current.startOfDay(for: Date(ms: $0.start)) }
        let days = byDay.keys.sorted(by: >)

        return ScrollView {
            VStack(spacing: 26) {
                // Month summary
                VStack(spacing: 2) {
                    HStack {
                        roundButton("chevron.left") { withAnimation { month = month.shifted(by: -1) } }
                        Spacer()
                        Button(month.title) { withAnimation { month = .current } }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        roundButton("chevron.right") { withAnimation { month = month.shifted(by: 1) } }
                    }
                    .padding(.bottom, 10)
                    Text("Time worked").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    Text(dur(total)).font(.system(size: 40, weight: .semibold)).monospacedDigit()
                    Group {
                        if list.isEmpty {
                            Text("\(money(p.rate))/hr")
                        } else {
                            Text("\(list.count) \(list.count == 1 ? "session" : "sessions") · Bills as ")
                                + Text("\(hours) h × \(money(p.rate)) = \(money(hours * p.rate))").foregroundColor(Theme.ink).bold()
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                }
                .padding(18)
                .card()

                // Work log
                VStack(spacing: 10) {
                    SectionHeader(title: "Work log") {
                        Button("+ Add") { entrySheet = SheetEntry(entry: nil) }
                            .buttonStyle(SmallPillStyle())
                    }
                    if days.isEmpty {
                        Text("No work logged in \(month.name).")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(26)
                            .card()
                    }
                    ForEach(days, id: \.self) { day in
                        let sessions = (byDay[day] ?? []).sorted { $0.start < $1.start }
                        VStack(spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(dayLabel(day)).font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text(dur(sessions.reduce(0) { $0 + $1.worked }))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 6)
                            ForEach(sessions) { e in
                                EntryCard(entry: e) {
                                    entrySheet = SheetEntry(entry: e)
                                } onPhoto: { i in
                                    viewer = ViewerItem(ids: e.photos, index: i)
                                }
                            }
                        }
                        .padding(.top, 12)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle(p.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    projectSheet = SheetProject(project: p)
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit project")
            }
        }
    }

    private func roundButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(Theme.card, in: Circle())
                .overlay(Circle().stroke(Theme.border))
        }
    }
}

/// Rounded box: start → stop (top left), total worked (bottom left), photos (right), description (bottom).
struct EntryCard: View {
    let entry: Entry
    var onTap: () -> Void
    var onPhoto: (Int) -> Void

    var body: some View {
        let nextDay = !Calendar.current.isDate(Date(ms: entry.start), inSameDayAs: Date(ms: entry.end))
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(timeText(entry.start))
                        Text("→").foregroundStyle(Theme.muted).fontWeight(.regular)
                        Text(timeText(entry.end))
                        if nextDay { Text("+1d").foregroundStyle(Theme.muted).fontWeight(.regular) }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    if entry.breakMs > 0 {
                        Text("\(dur(entry.breakMs)) break")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 4)
                    }
                    Spacer(minLength: 10)
                    Text("Total worked").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                    Text(dur(entry.worked))
                        .font(.system(size: 26, weight: .semibold))
                        .monospacedDigit()
                }
                .padding(.leading, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

                PhotoMosaic(ids: entry.photos, onTap: onPhoto)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 124)

            Rectangle().fill(Theme.line).frame(height: 1)
            Text(entry.description.isEmpty ? "No description" : entry.description)
                .font(.system(size: 14))
                .foregroundStyle(entry.description.isEmpty ? Theme.muted : Color(hex: "#3A3A3F"))
                .lineSpacing(3)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .card(radius: 28)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// 1–4 photos filling the right half of an entry; "+N" when there are more.
struct PhotoMosaic: View {
    @ObservedObject private var store = Store.shared
    let ids: [String]
    var onTap: (Int) -> Void

    var body: some View {
        Group {
            switch min(ids.count, 4) {
            case 0:
                Theme.track.overlay(
                    Image(systemName: "camera").font(.system(size: 22)).foregroundStyle(Color(hex: "#C3C5CC"))
                )
            case 1:
                tile(0)
            case 2:
                HStack(spacing: 4) { tile(0); tile(1) }
            case 3:
                HStack(spacing: 4) {
                    tile(0)
                    VStack(spacing: 4) { tile(1); tile(2) }
                }
            default:
                VStack(spacing: 4) {
                    HStack(spacing: 4) { tile(0); tile(1) }
                    HStack(spacing: 4) { tile(2); tile(3) }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func tile(_ i: Int) -> some View {
        Theme.track
            .overlay {
                if let img = store.thumbnail(ids[i]) {
                    Image(uiImage: img).resizable().scaledToFill()
                }
            }
            .overlay {
                if i == 3 && ids.count > 4 {
                    ZStack {
                        Color.black.opacity(0.45)
                        Text("+\(ids.count - 4)").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { onTap(i) }
    }
}

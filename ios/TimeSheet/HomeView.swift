import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SheetProject: Identifiable {
    let id = UUID()
    var project: Project?
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct HomeView: View {
    @ObservedObject private var store = Store.shared
    @State private var projectSheet: SheetProject?
    @State private var showImporter = false
    @State private var pendingImport: BackupFile?
    @State private var share: ShareItem?
    @State private var message: String?

    var body: some View {
        let month = Month.current
        let monthEntries = store.db.entries.filter { month.contains(ms: $0.start) }
        let total = monthEntries.reduce(0) { $0 + $1.worked }
        let projectCount = Set(monthEntries.map(\.projectId)).count

        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 2) {
                    Text("Worked in \(month.name)").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    Text(dur(total)).font(.system(size: 40, weight: .semibold)).monospacedDigit()
                    Text(monthEntries.isEmpty
                         ? "No sessions yet this month"
                         : "\(monthEntries.count) \(monthEntries.count == 1 ? "session" : "sessions") across \(projectCount) \(projectCount == 1 ? "project" : "projects")")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .card()

                VStack(spacing: 10) {
                    SectionHeader(title: "Projects") {
                        Button("+ New") { projectSheet = SheetProject(project: nil) }
                            .buttonStyle(SmallPillStyle())
                    }
                    projectList(month: month)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Time Sheet")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        do { share = ShareItem(url: try store.makeBackup()) } catch { message = "Could not create the backup." }
                    } label: { Label("Export backup", systemImage: "square.and.arrow.up") }
                    Button {
                        showImporter = true
                    } label: { Label("Import backup", systemImage: "square.and.arrow.down") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $projectSheet) { item in
            ProjectSheet(existing: item.project)
        }
        .sheet(item: $share) { item in
            ShareSheet(url: item.url).presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            do {
                pendingImport = try Store.readBackup(try result.get())
            } catch {
                message = "That file is not a valid Time Sheet backup."
            }
        }
        .alert("Restore backup?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("Cancel", role: .cancel) { pendingImport = nil }
            Button("Restore") {
                if let backup = pendingImport {
                    Task { await store.restore(backup) }
                }
                pendingImport = nil
            }
        } message: {
            Text("This replaces everything in the app with the backup (\(pendingImport?.projects.count ?? 0) projects, \(pendingImport?.entries.count ?? 0) sessions). Use the backup file exported from the web app to bring your hours over.")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func projectList(month: Month) -> some View {
        if store.db.projects.isEmpty {
            Text("No projects yet.\nTap + New to create your first one.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(26)
                .card()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(store.db.projects.enumerated()), id: \.element.id) { index, p in
                    if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    NavigationLink(value: p.id) {
                        ProjectRow(project: p, month: month)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .card()
        }
    }
}

struct ProjectRow: View {
    @ObservedObject private var store = Store.shared
    let project: Project
    let month: Month

    var body: some View {
        let running = store.db.active?.projectId == project.id
        let meta = [project.client, "\(money(project.rate))/hr"].filter { !$0.isEmpty }.joined(separator: " · ")
        HStack(spacing: 14) {
            ProjectDot(hex: project.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                HStack(spacing: 4) {
                    if running {
                        Text("●").foregroundStyle(Theme.danger)
                        Text("Timer running ·")
                    }
                    Text(meta)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(dur(store.entries(of: project.id, in: month).reduce(0) { $0 + $1.worked }))
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Text("this month").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

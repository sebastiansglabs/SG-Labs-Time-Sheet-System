import ActivityKit
import SwiftUI
import UIKit
import UserNotifications

/// All app data and actions. Saved as JSON in the app's Documents folder; photos as JPEG files next to it.
/// Also keeps the lock screen / Dynamic Island timer (Live Activity) in step with the real timer.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var db: Database { didSet { save() } }
    @Published var timerOpen = false
    @Published var draftProjectId: String?
    @Published var draftDescription = ""

    private let fileURL: URL
    let photosDir: URL
    private let thumbs = NSCache<NSString, UIImage>()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("timesheet.json")
        photosDir = docs.appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode(Database.self, from: data) {
            db = saved
        } else {
            db = Database()
        }
    }

    private func save() {
        do {
            try JSONEncoder().encode(db).write(to: fileURL, options: .atomic)
        } catch {
            print("Save failed: \(error)")
        }
    }

    // MARK: - Lookups

    func project(_ id: String?) -> Project? {
        guard let id else { return nil }
        return db.projects.first { $0.id == id }
    }

    func entries(of projectId: String, in month: Month? = nil) -> [Entry] {
        db.entries.filter { $0.projectId == projectId && (month?.contains(ms: $0.start) ?? true) }
    }

    // MARK: - Timer

    var isPaused: Bool { db.active?.isPaused ?? false }

    /// Time worked so far on the active session, in ms.
    func elapsed(at now: Double = nowMs()) -> Double {
        guard let a = db.active else { return 0 }
        let until = a.end ?? now
        return max(0, until - a.start - breakTotal(a.breaks, until: until))
    }

    func openTimer(preferring projectId: String? = nil) {
        if db.active == nil {
            if let projectId, project(projectId) != nil {
                draftProjectId = projectId
            } else if project(draftProjectId) == nil {
                draftProjectId = db.projects.last?.id
            }
        }
        timerOpen = true
    }

    func start() async {
        guard db.active == nil, let pid = draftProjectId, project(pid) != nil else { return }
        db.active = ActiveTimer(
            projectId: pid,
            description: draftDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            start: nowMs()
        )
        draftDescription = ""
        // Asked once, so a stop from the lock screen can remind you to add photos
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await syncActivity()
    }

    func togglePause() async {
        guard var a = db.active, a.end == nil else { return }
        let now = nowMs()
        if let last = a.breaks.indices.last, a.breaks[last].end == nil {
            a.breaks[last].end = now
        } else {
            a.breaks.append(Break(start: now, end: nil))
        }
        db.active = a
        await syncActivity()
    }

    func stop(fromLockScreen: Bool = false) async {
        guard var a = db.active, a.end == nil else { return }
        // Stopping while paused ends the session when the pause began
        if let last = a.breaks.last, last.end == nil {
            a.end = last.start
            a.breaks.removeLast()
        } else {
            a.end = nowMs()
        }
        db.active = a
        await endActivities()
        if fromLockScreen { notifyStopped() }
    }

    /// Undo a Stop: the gap between Stop and Resume counts as a break.
    func resume() async {
        guard var a = db.active, let end = a.end else { return }
        a.breaks.append(Break(start: end, end: nowMs()))
        a.end = nil
        db.active = a
        await syncActivity()
    }

    func saveActive() -> Entry? {
        guard let a = db.active, let end = a.end else { return nil }
        let entry = Entry(
            projectId: a.projectId,
            start: a.start,
            end: end,
            breakMs: breakTotal(a.breaks, until: end),
            description: a.description.trimmingCharacters(in: .whitespacesAndNewlines),
            photos: a.photos
        )
        db.entries.append(entry)
        db.active = nil
        return entry
    }

    func discardActive() async {
        guard let a = db.active else { return }
        deletePhotos(a.photos)
        db.active = nil
        await endActivities()
    }

    /// App came to the front: refresh, and show the photo/save screen if the timer was stopped from the lock screen.
    func becameActive() {
        objectWillChange.send()
        if db.active?.end != nil { timerOpen = true }
        Task { await syncActivity() }
    }

    // MARK: - Live Activity (lock screen + Dynamic Island)

    private func contentState(_ a: ActiveTimer) -> TimerAttributes.ContentState {
        let now = nowMs()
        let shifted = Date(ms: a.start + breakTotal(a.breaks, until: now))
        return TimerAttributes.ContentState(countFrom: shifted, pausedElapsed: a.isPaused ? elapsed(at: now) / 1000 : nil)
    }

    func syncActivity() async {
        guard let a = db.active, a.end == nil, let p = project(a.projectId) else {
            await endActivities()
            return
        }
        let content = ActivityContent(state: contentState(a), staleDate: nil)
        let live = Activity<TimerAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
        if let current = live.first(where: { $0.attributes.projectName == p.name && $0.attributes.colorHex == p.color }) {
            await current.update(content)
            for other in live where other.id != current.id {
                await other.end(nil, dismissalPolicy: .immediate)
            }
            return
        }
        await endActivities()
        // A new one can only be started while the app is open; the system ends them after about 8 hours.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity<TimerAttributes>.request(
                attributes: TimerAttributes(projectName: p.name, colorHex: p.color),
                content: content,
                pushType: nil
            )
        } catch {
            print("Live Activity not started: \(error)")
        }
    }

    private func endActivities() async {
        for activity in Activity<TimerAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func notifyStopped() {
        guard let a = db.active, a.end != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Timer stopped · \(dur(elapsed()))"
        content.body = "\(project(a.projectId)?.name ?? "Project"): open Time Sheet to add a photo and save it to the log."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "stopped", content: content, trigger: nil))
    }

    // MARK: - Projects & entries

    func saveProject(_ p: Project) {
        if let i = db.projects.firstIndex(where: { $0.id == p.id }) {
            db.projects[i] = p
        } else {
            db.projects.append(p)
        }
        if db.active?.projectId == p.id { Task { await syncActivity() } }
    }

    func deleteProject(_ p: Project) {
        let gone = entries(of: p.id)
        deletePhotos(gone.flatMap(\.photos))
        db.entries.removeAll { $0.projectId == p.id }
        db.projects.removeAll { $0.id == p.id }
    }

    func saveEntry(_ e: Entry) {
        if let i = db.entries.firstIndex(where: { $0.id == e.id }) {
            db.entries[i] = e
        } else {
            db.entries.append(e)
        }
    }

    func deleteEntry(_ e: Entry) {
        deletePhotos(e.photos)
        db.entries.removeAll { $0.id == e.id }
    }

    // MARK: - Photos

    func photoURL(_ id: String) -> URL { photosDir.appendingPathComponent(id + ".jpg") }

    /// Shrinks to 1600px and stores as JPEG. Returns the new photo id.
    func addPhoto(_ image: UIImage) -> String? {
        let id = makeID()
        guard let data = image.shrunk(maxSide: 1600).jpegData(compressionQuality: 0.82) else { return nil }
        do {
            try data.write(to: photoURL(id), options: .atomic)
            return id
        } catch {
            return nil
        }
    }

    func image(_ id: String) -> UIImage? { UIImage(contentsOfFile: photoURL(id).path) }

    /// Small version for lists, cached.
    func thumbnail(_ id: String) -> UIImage? {
        if let hit = thumbs.object(forKey: id as NSString) { return hit }
        guard let full = image(id), let small = full.preparingThumbnail(of: full.size.fitting(maxSide: 400)) else { return nil }
        thumbs.setObject(small, forKey: id as NSString)
        return small
    }

    func deletePhotos(_ ids: [String]) {
        for id in ids {
            try? FileManager.default.removeItem(at: photoURL(id))
            thumbs.removeObject(forKey: id as NSString)
        }
    }

    // MARK: - Backup (same file format as the web app)

    func makeBackup() throws -> URL {
        var photos: [String: String] = [:]
        let ids = db.entries.flatMap(\.photos) + (db.active?.photos ?? [])
        for id in ids {
            if let data = try? Data(contentsOf: photoURL(id)) {
                photos[id] = "data:image/jpeg;base64," + data.base64EncodedString()
            }
        }
        let file = BackupFile(projects: db.projects, entries: db.entries, active: db.active, photos: photos)
        let day = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("timesheet-backup-\(day).json")
        try JSONEncoder().encode(file).write(to: url, options: .atomic)
        return url
    }

    static func readBackup(_ url: URL) throws -> BackupFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try JSONDecoder().decode(BackupFile.self, from: Data(contentsOf: url))
    }

    func restore(_ backup: BackupFile) async {
        await endActivities()
        if let old = try? FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil) {
            for f in old { try? FileManager.default.removeItem(at: f) }
        }
        thumbs.removeAllObjects()
        for (id, dataURL) in backup.photos ?? [:] {
            guard let comma = dataURL.firstIndex(of: ",") else { continue }
            if let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) {
                try? data.write(to: photoURL(id), options: .atomic)
            }
        }
        var restored = Database()
        restored.projects = backup.projects
        restored.entries = backup.entries
        restored.active = backup.active
        db = restored
        await syncActivity()
    }
}

extension UIImage {
    func shrunk(maxSide: CGFloat) -> UIImage {
        let target = size.fitting(maxSide: maxSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Drawing also bakes in the camera's rotation
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

extension CGSize {
    func fitting(maxSide: CGFloat) -> CGSize {
        let k = min(1, maxSide / max(width, height, 1))
        return CGSize(width: (width * k).rounded(), height: (height * k).rounded())
    }
}

import Foundation

// Same shape as the web app's data (timestamps in milliseconds, money in cents),
// so a web backup file imports directly.

struct Project: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var client: String
    var rate: Int        // cents per hour
    var color: String    // "#RRGGBB"
    var createdAt: Double

    init(id: String = makeID(), name: String, client: String, rate: Int, color: String, createdAt: Double = nowMs()) {
        self.id = id
        self.name = name
        self.client = client
        self.rate = rate
        self.color = color
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey { case id, name, client, rate, color, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Project"
        client = try c.decodeIfPresent(String.self, forKey: .client) ?? ""
        rate = Int(try c.decodeIfPresent(Double.self, forKey: .rate) ?? Double(defaultRate))
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? projectColors[0]
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
    }
}

struct Entry: Codable, Identifiable, Hashable {
    var id: String
    var projectId: String
    var start: Double    // ms
    var end: Double      // ms
    var breakMs: Double
    var description: String
    var photos: [String]

    var worked: Double { max(0, end - start - breakMs) }

    init(id: String = makeID(), projectId: String, start: Double, end: Double, breakMs: Double, description: String, photos: [String]) {
        self.id = id
        self.projectId = projectId
        self.start = start
        self.end = end
        self.breakMs = breakMs
        self.description = description
        self.photos = photos
    }

    enum CodingKeys: String, CodingKey { case id, projectId, start, end, breakMs, description, photos }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        projectId = try c.decode(String.self, forKey: .projectId)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        breakMs = try c.decodeIfPresent(Double.self, forKey: .breakMs) ?? 0
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        photos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
    }
}

struct Break: Codable, Hashable {
    var start: Double
    var end: Double?
}

/// The session on the clock right now (or stopped and waiting to be saved).
struct ActiveTimer: Codable, Hashable {
    var projectId: String
    var description: String
    var start: Double
    var breaks: [Break]
    var end: Double?
    var photos: [String]

    init(projectId: String, description: String, start: Double) {
        self.projectId = projectId
        self.description = description
        self.start = start
        self.breaks = []
        self.end = nil
        self.photos = []
    }

    enum CodingKeys: String, CodingKey { case projectId, description, start, breaks, end, photos }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectId = try c.decode(String.self, forKey: .projectId)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        start = try c.decode(Double.self, forKey: .start)
        breaks = try c.decodeIfPresent([Break].self, forKey: .breaks) ?? []
        end = try c.decodeIfPresent(Double.self, forKey: .end)
        photos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
    }

    var isPaused: Bool { end == nil && breaks.last.map { $0.end == nil } == true }
}

struct Database: Codable {
    var projects: [Project] = []
    var entries: [Entry] = []
    var active: ActiveTimer?

    init() {}

    enum CodingKeys: String, CodingKey { case projects, entries, active }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        active = try c.decodeIfPresent(ActiveTimer.self, forKey: .active)
    }
}

/// Backup file: the database plus every photo as a data URL (same as the web app's export).
struct BackupFile: Codable {
    var projects: [Project]
    var entries: [Entry]
    var active: ActiveTimer?
    var photos: [String: String]?
}

// MARK: - Helpers

let defaultRate = 3000 // $30.00/hr
let projectColors = ["#E07A5F", "#3D8B7D", "#E3B04B", "#6A8FC7", "#A26EA1", "#8DB596", "#E89AAE", "#1C1C1E"]

func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

func makeID() -> String {
    String(Int(nowMs()), radix: 36) + String(Int.random(in: 0..<60_466_176), radix: 36)
}

func breakTotal(_ breaks: [Break], until: Double) -> Double {
    breaks.reduce(0) { $0 + (($1.end ?? until) - $1.start) }
}

extension Date {
    init(ms: Double) { self.init(timeIntervalSince1970: ms / 1000) }
    var ms: Double { timeIntervalSince1970 * 1000 }
}

struct Month: Hashable {
    var year: Int
    var month: Int // 1–12

    static var current: Month { Month(date: Date()) }

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(date: Date) {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        self.init(year: c.year ?? 2026, month: c.month ?? 1)
    }

    var firstDay: Date { Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date() }

    func shifted(by months: Int) -> Month {
        Month(date: Calendar.current.date(byAdding: .month, value: months, to: firstDay) ?? firstDay)
    }

    func contains(ms: Double) -> Bool { Month(date: Date(ms: ms)) == self }

    var title: String { firstDay.formatted(.dateTime.month(.wide).year()) }
    var name: String { firstDay.formatted(.dateTime.month(.wide)) }
}

// MARK: - Formatting

/// "6h 58m" / "45m"
func dur(_ ms: Double) -> String {
    let m = Int(max(0, ms) / 60_000)
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
}

/// "4:30 PM"
func timeText(_ ms: Double) -> String {
    Date(ms: ms).formatted(date: .omitted, time: .shortened)
}

func money(_ cents: Int) -> String {
    (Double(cents) / 100).formatted(.currency(code: "USD"))
}

/// Billing rounds the exact total UP to the next full hour (4h 10m → 5 h). The log shows exact times.
func billedHours(_ ms: Double) -> Int {
    let minutes = Int(max(0, ms) / 60_000)
    return Int((Double(minutes) / 60).rounded(.up))
}

func dayLabel(_ day: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(day) { return "Today" }
    if cal.isDateInYesterday(day) { return "Yesterday" }
    return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
}

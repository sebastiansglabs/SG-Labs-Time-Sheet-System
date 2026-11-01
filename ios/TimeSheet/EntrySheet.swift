import SwiftUI

/// Edit a logged session, or add one by hand.
struct EntrySheet: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    let existing: Entry?

    @State private var projectId: String
    @State private var start: Date
    @State private var end: Date
    @State private var breakMinutes: String
    @State private var text: String
    @State private var photos: [String]
    @State private var added: [String] = []   // photos added in this sheet (deleted again on Cancel)
    @State private var removed: [String] = [] // existing photos removed (deleted for real on Save)
    @State private var saved = false
    @State private var confirmDelete = false

    init(existing: Entry?, defaultProjectId: String) {
        self.existing = existing
        let stop = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 300).rounded(.down) * 300)
        _projectId = State(initialValue: existing?.projectId ?? defaultProjectId)
        _start = State(initialValue: existing.map { Date(ms: $0.start) } ?? stop.addingTimeInterval(-3600))
        _end = State(initialValue: existing.map { Date(ms: $0.end) } ?? stop)
        _breakMinutes = State(initialValue: existing.map { $0.breakMs > 0 ? String(Int($0.breakMs / 60_000)) : "" } ?? "")
        _text = State(initialValue: existing?.description ?? "")
        _photos = State(initialValue: existing?.photos ?? [])
    }

    private var breakMs: Double { Double(Int(breakMinutes) ?? 0) * 60_000 }

    private var problem: String? {
        if end <= start { return "Stop time must be after the start time" }
        if breakMs >= (end.ms - start.ms) { return "Breaks are longer than the session" }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Project", selection: $projectId) {
                        ForEach(store.db.projects) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                }
                Section {
                    DatePicker("Started", selection: $start)
                    DatePicker("Stopped", selection: $end)
                    HStack {
                        Text("Breaks")
                        Spacer()
                        TextField("0", text: $breakMinutes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("min").foregroundStyle(Theme.muted)
                    }
                } footer: {
                    Text(problem ?? "\(dur(end.ms - start.ms - breakMs)) worked")
                        .foregroundStyle(problem == nil ? Theme.muted : Theme.danger)
                }
                Section("Description") {
                    TextField("Description (optional)", text: $text, axis: .vertical)
                        .lineLimit(2...8)
                }
                Section("Photos") {
                    PhotoEditor(ids: $photos, onAdd: { added.append($0) }, onRemove: { id in
                        if let i = added.firstIndex(of: id) {
                            added.remove(at: i)
                            store.deletePhotos([id])
                        } else {
                            removed.append(id)
                        }
                    })
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }
                if existing != nil {
                    Section {
                        Button("Delete entry", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add entry" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(problem != nil)
                }
            }
            .alert("Delete this entry?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let e = existing {
                        store.deletePhotos(added)
                        store.deleteEntry(e)
                        saved = true
                    }
                    dismiss()
                }
            } message: {
                Text("Its photos are deleted too.")
            }
        }
        .onDisappear {
            if !saved { store.deletePhotos(added) }
        }
    }

    private func save() {
        var e = existing ?? Entry(projectId: projectId, start: 0, end: 0, breakMs: 0, description: "", photos: [])
        e.projectId = projectId
        e.start = start.ms
        e.end = end.ms
        e.breakMs = breakMs
        e.description = text.trimmingCharacters(in: .whitespacesAndNewlines)
        e.photos = photos
        store.saveEntry(e)
        store.deletePhotos(removed)
        saved = true
        dismiss()
    }
}

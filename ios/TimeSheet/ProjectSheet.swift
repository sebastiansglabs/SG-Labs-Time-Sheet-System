import SwiftUI

struct ProjectSheet: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    let existing: Project?
    var onSaved: (Project) -> Void = { _ in }
    var onDeleted: () -> Void = {}

    @State private var name: String
    @State private var client: String
    @State private var rate: String
    @State private var color: String
    @State private var confirmDelete = false
    @State private var blocked = false

    init(existing: Project?, onSaved: @escaping (Project) -> Void = { _ in }, onDeleted: @escaping () -> Void = {}) {
        self.existing = existing
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _name = State(initialValue: existing?.name ?? "")
        _client = State(initialValue: existing?.client ?? "")
        _rate = State(initialValue: String(format: "%.2f", Double(existing?.rate ?? defaultRate) / 100))
        _color = State(initialValue: existing?.color ?? projectColors[Store.shared.db.projects.count % projectColors.count])
    }

    private var rateCents: Int? {
        let cleaned = rate.replacingOccurrences(of: ",", with: ".").filter { "0123456789.".contains($0) }
        if cleaned.isEmpty { return defaultRate }
        guard let value = Double(cleaned), value >= 0 else { return nil }
        return Int((value * 100).rounded())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project name, e.g. Website redesign", text: $name)
                    TextField("Client (optional)", text: $client)
                }
                Section {
                    HStack {
                        Text("Hourly rate")
                        Spacer()
                        Text("$").foregroundStyle(Theme.muted)
                        TextField("30.00", text: $rate)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                }
                Section("Color") {
                    HStack {
                        ForEach(projectColors, id: \.self) { c in
                            Circle()
                                .fill(Color(hex: c))
                                .frame(width: 30, height: 30)
                                .padding(3)
                                .overlay(Circle().stroke(c == color ? Color(hex: c) : .clear, lineWidth: 2))
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture { color = c }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if existing != nil {
                    Section {
                        Button("Delete project", role: .destructive) {
                            if store.db.active?.projectId == existing?.id { blocked = true } else { confirmDelete = true }
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New project" : "Edit project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || rateCents == nil)
                }
            }
            .alert("Delete \"\(existing?.name ?? "")\"?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let p = existing { store.deleteProject(p) }
                    dismiss()
                    onDeleted()
                }
            } message: {
                let count = existing.map { store.entries(of: $0.id).count } ?? 0
                Text(count == 0
                     ? "This project has no logged work."
                     : "This also deletes its \(count) logged \(count == 1 ? "session" : "sessions") and their photos. This can't be undone.")
            }
            .alert("Timer is running", isPresented: $blocked) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Stop the timer on this project before deleting it.")
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard let cents = rateCents else { return }
        var p = existing ?? Project(name: "", client: "", rate: cents, color: color)
        p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        p.client = client.trimmingCharacters(in: .whitespacesAndNewlines)
        p.rate = cents
        p.color = color
        store.saveProject(p)
        dismiss()
        onSaved(p)
    }
}

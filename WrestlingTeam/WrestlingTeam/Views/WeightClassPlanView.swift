import SwiftUI

/// The portal's before/after-Christmas weight class form. Saves to the separate weight class plans sheet.
struct WeightClassPlanView: View {
    @EnvironmentObject var store: PortalStore
    @State private var info: WeightPlanInfo?
    @State private var before = ""
    @State private var after = ""
    @State private var current = ""
    @State private var notes = ""
    @State private var status: String?
    @State private var working = false

    var body: some View {
        Form {
            if let info {
                Section {
                    Picker("Before Christmas", selection: $before) {
                        Text("Pick one").tag("")
                        ForEach(info.classes, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("After Christmas", selection: $after) {
                        Text("Pick one").tag("")
                        ForEach(info.classes, id: \.self) { Text($0).tag($0) }
                    }
                } header: { Text("Weight class you plan to wrestle") }
                Section("Current weight (optional)") {
                    TextField("e.g. 147.5", text: $current).keyboardType(.decimalPad)
                }
                Section("Notes for Coach (optional)") {
                    TextField("Anything Coach should know", text: $notes, axis: .vertical).lineLimit(2...5)
                }
                Section {
                    Button { Task { await save() } } label: {
                        HStack { Text(info.plan == nil ? "Submit" : "Update My Plan"); if working { Spacer(); ProgressView() } }
                    }
                    .disabled(before.isEmpty || after.isEmpty || working)
                } footer: {
                    if let status { Text(status) }
                    else if let saved = info.plan?.saved, !saved.isEmpty { Text("Last saved \(saved). Submitting again updates it.") }
                }
            } else if let status {
                Text(status).foregroundStyle(Theme.red)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Weight Class Plan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let i = try await store.api.weightPlan()
            info = i
            if let p = i.plan { before = p.before; after = p.after; current = p.current; notes = p.notes }
        } catch { status = error.localizedDescription }
    }

    private func save() async {
        working = true
        defer { working = false }
        do {
            try await store.api.saveWeightPlan(before: before, after: after, current: current, notes: notes)
            status = "Saved. Thanks!"
            info = try? await store.api.weightPlan()
        } catch { status = error.localizedDescription }
    }
}

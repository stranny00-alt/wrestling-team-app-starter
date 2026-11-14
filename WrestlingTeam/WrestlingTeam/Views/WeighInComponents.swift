import SwiftUI
import Charts

/// Weigh-ins over time: before practice (and other/older entries) in red, after practice in gold, and the descent plan's
/// "lowest eligible weight" as a dashed step line when there is one.
struct WeighInChart: View {
    var entries: [WeighIn]
    var plan: DescentPlan?
    var title = "Weigh-Ins"

    var body: some View {
        let points = entries.sorted { $0.date < $1.date }
        Card(title: title) {
            if points.count < 2 {
                Text(points.isEmpty ? "No weigh-ins yet." : "The chart appears after a second weigh-in.")
                    .font(.subheadline).foregroundStyle(Theme.gray)
            } else {
                let first = points.first!.date, last = points.last!.date
                let steps = (plan?.steps ?? []).filter { s in
                    guard let d = s.day else { return false }
                    return d <= last.addingTimeInterval(7 * 86_400) && d >= first.addingTimeInterval(-7 * 86_400)
                }
                let all = points.map(\.weight) + steps.map(\.weight)
                let lo = (all.min() ?? 100) - 2, hi = (all.max() ?? 200) + 2
                Chart {
                    ForEach(steps) { s in
                        LineMark(x: .value("Date", s.day!), y: .value("Lbs", s.weight), series: .value("Series", "Plan"))
                            .interpolationMethod(.stepEnd)
                            .foregroundStyle(Theme.gray.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                    ForEach(points.filter { !$0.isAfterPractice }) { w in
                        LineMark(x: .value("Date", w.date), y: .value("Lbs", w.weight), series: .value("Series", "Before"))
                            .foregroundStyle(Theme.red)
                        PointMark(x: .value("Date", w.date), y: .value("Lbs", w.weight)).foregroundStyle(Theme.red).symbolSize(28)
                    }
                    ForEach(points.filter(\.isAfterPractice)) { w in
                        LineMark(x: .value("Date", w.date), y: .value("Lbs", w.weight), series: .value("Series", "After"))
                            .foregroundStyle(Theme.gold)
                        PointMark(x: .value("Date", w.date), y: .value("Lbs", w.weight)).foregroundStyle(Theme.gold).symbolSize(28)
                    }
                }
                .chartYScale(domain: lo...hi)
                .frame(height: 200)
                HStack(spacing: 14) {
                    if points.contains(where: \.isAfterPractice) {
                        Label("Before practice", systemImage: "circle.fill").foregroundStyle(Theme.red)
                        Label("After", systemImage: "circle.fill").foregroundStyle(Theme.gold)
                    } else {
                        Label("Weigh-ins", systemImage: "circle.fill").foregroundStyle(Theme.red)
                    }
                    if !steps.isEmpty { Label("Plan", systemImage: "line.diagonal").foregroundStyle(Theme.gray) }
                }
                .font(.caption2)
            }
        }
    }
}

/// Newest-first list of weigh-ins. After-practice entries show what was lost at practice (vs. that day's before);
/// the others show the change from the previous weigh-in of the same kind.
struct WeighInHistory: View {
    var entries: [WeighIn]
    var limit = 30
    /// Coaches: tap an entry to fix or delete it.
    var onEdit: ((WeighIn) -> Void)? = nil

    var body: some View {
        let list = entries.sorted { $0.date > $1.date }
        Card(title: "History") {
            if list.isEmpty {
                Text("No weigh-ins yet.").foregroundStyle(Theme.gray)
            } else {
                ForEach(Array(list.prefix(limit).enumerated()), id: \.element.id) { i, w in
                    if let onEdit {
                        Button { onEdit(w) } label: { row(w, editable: true) }.buttonStyle(.plain)
                    } else {
                        row(w, editable: false)
                    }
                    if i < min(list.count, limit) - 1 { Divider() }
                }
                Text(onEdit != nil
                     ? "Tap an entry to fix or delete it. COACH marks weights a coach punched in; the rest are self-reported."
                     : "Self-reported weights (COACH marks ones a coach entered), kept separate from official weigh-ins and certification. Changes compare before-practice weights with each other; after-practice entries show what was lost at practice.")
                    .font(.caption).foregroundStyle(Theme.gray).padding(.top, 4)
            }
        }
    }
}

extension WeighInHistory {
    @ViewBuilder fileprivate func row(_ w: WeighIn, editable: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(w.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(.subheadline)
                    if w.isCoachEntry { Tag(text: "COACH", color: Theme.red) }
                    if w.wasEdited { Tag(text: "EDITED", color: Theme.gray) }
                }
                Text(w.date.formatted(date: .omitted, time: .shortened) + " · " + w.whenLabel).font(.caption).foregroundStyle(Theme.gray)
            }
            Spacer()
            if let loss = entries.practiceLoss(for: w) {
                Text((loss >= 0 ? "−" : "+") + abs(loss).lbs + " at practice").font(.caption.bold()).foregroundStyle(Theme.goldText)
            } else if let prev = entries.previous(sameKindAs: w) {
                ChangeText(change: w.weight - prev.weight)
            }
            Text(w.weight.lbs).font(Theme.display(22)).frame(minWidth: 60, alignment: .trailing)
            if editable { Image(systemName: "pencil").font(.caption).foregroundStyle(Theme.gray) }
        }
        .contentShape(Rectangle())
    }
}

/// Small outlined label, e.g. COACH / EDITED.
struct Tag: View {
    var text: String
    var color: Color
    var body: some View {
        Text(text).font(.system(size: 9, weight: .bold)).tracking(0.4)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .foregroundStyle(color)
            .overlay(Capsule().stroke(color.opacity(0.6)))
    }
}

/// Coaches: fix a weigh-in (weight, before/after) or delete it. The sheet keeps a note of the old value.
struct EditWeighInView: View {
    @EnvironmentObject var store: PortalStore
    @Environment(\.dismiss) private var dismiss
    var name: String
    var email: String
    var entry: WeighIn

    @State private var text = ""
    @State private var when: WeighInWhen = .other
    @State private var working = false
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Logged", value: entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    LabeledContent("By", value: entry.isCoachEntry ? "Coach" : "\(name) (self-reported)")
                } header: { Text(name) }
                Section("Weight") {
                    HStack {
                        TextField("000.0", text: $text).keyboardType(.decimalPad).font(Theme.display(34))
                        Text("lbs").foregroundStyle(Theme.gray)
                    }
                    Picker("When", selection: $when) {
                        ForEach(WeighInWhen.allCases) { Text($0.label).tag($0) }
                    }
                }
                if let note = entry.edited, !note.isEmpty {
                    Section("Earlier changes") { Text(note).font(.caption).foregroundStyle(Theme.gray) }
                }
                if let error { Section { Text(error).foregroundStyle(Theme.red) } }
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete This Weigh-In", systemImage: "trash") }
                        .disabled(working)
                        .confirmationDialog("Delete this weigh-in?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete \(entry.weight.lbs) lbs", role: .destructive) { Task { await delete() } }
                        } message: {
                            Text("\(name), \(entry.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())). This removes the row from the sheet.")
                        }
                } footer: {
                    Text("Saving a change keeps a note of the old value in the sheet's Edited column. Deleting removes the row from the Weigh-Ins tab.")
                }
            }
            .navigationTitle("Fix Weigh-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working { ProgressView() } else { Button("Save") { Task { await save() } }.bold().disabled(parsed == nil) }
                }
            }
        }
        .onAppear { text = entry.weight.lbs; when = entry.kind ?? .other }
    }

    private var parsed: Double? {
        guard let w = WeighInCheck.parse(text), (WeighInCheck.minWeight...WeighInCheck.maxWeight).contains(w) else { return nil }
        return w
    }

    private func save() async {
        guard let w = parsed else { return }
        working = true; error = nil
        defer { working = false }
        do {
            // Older rows have no before/after; leave that alone unless the coach picked something.
            let newWhen: WeighInWhen? = entry.kind == nil && when == .other ? nil : when
            _ = try await store.editWeighIn(email: email, entry: entry, weight: w, when: newWhen)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func delete() async {
        working = true; error = nil
        defer { working = false }
        do { try await store.deleteWeighIn(email: email, entry: entry); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

/// "+0.4" / "−1.2" / "±0", gray.
struct ChangeText: View {
    var change: Double
    var body: some View {
        Text(change == 0 ? "±0" : (change > 0 ? "+" : "−") + abs(change).lbs).font(.caption).foregroundStyle(Theme.gray)
    }
}

extension Date {
    /// "Today", "Yesterday", "3 days ago", or "Nov 2".
    var shortAgo: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Today" }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: self), to: cal.startOfDay(for: Date())).day ?? 0
        return days < 7 ? "\(days) days ago" : formatted(.dateTime.month(.abbreviated).day())
    }
}

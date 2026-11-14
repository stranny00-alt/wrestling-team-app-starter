import SwiftUI

/// Log a weight. Wrestlers log their own (self-reported); a coach can punch one in for a wrestler (`wrestler` set).
struct LogWeightView: View {
    @EnvironmentObject var store: PortalStore
    /// Coach mode: the wrestler being weighed in. Nil = the signed-in wrestler logging their own weight.
    var wrestler: (name: String, email: String)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var issues: [WeighInCheck.Issue] = []
    @State private var confirming = false
    @State private var saving = false
    @State private var saveError: String?
    @State private var saved: WeighIn?
    @State private var when: WeighInWhen = .before
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let saved {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.ok)
                    Text("\(saved.weight.lbs) lbs logged").font(Theme.display(30))
                    Text(saved.whenLabel).font(.headline).foregroundStyle(Theme.gray)
                    if let loss = history.practiceLoss(for: saved), let before = history.beforePractice(matching: saved) {
                        VStack(spacing: 4) {
                            Text(loss >= 0 ? "−\(loss.lbs) lbs at practice" : "+\((-loss).lbs) lbs at practice").font(Theme.display(26)).foregroundStyle(Theme.red)
                            Text("\(before.weight.lbs) before → \(saved.weight.lbs) after (\(String(format: "%.1f", abs(loss) / before.weight * 100))%)")
                                .font(.subheadline).foregroundStyle(Theme.gray)
                        }
                        .padding(14).frame(maxWidth: .infinity).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text(wrestler == nil ? "Saved to the team sheet as self-reported." : "Saved to the team sheet as a coach weigh-in for \(firstName).")
                        .foregroundStyle(Theme.gray).multilineTextAlignment(.center)
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent).tint(Theme.red).controlSize(.large)
                } else {
                    entry
                }
            }
            .readableWidth(560)
            .padding()
            .screenBackground()
            .navigationTitle(wrestler == nil ? "Log My Weight" : "Weigh In \(firstName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { if saved == nil { Button("Cancel") { dismiss() } } } }
        }
        .onAppear { focused = true; when = history.suggestedWhen() }
    }

    private var entry: some View {
        VStack(spacing: 16) {
            Picker("When", selection: $when) {
                ForEach(WeighInWhen.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: when) { _, _ in issues = []; confirming = false; saveError = nil }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("000.0", text: $text)
                    .keyboardType(.decimalPad)
                    .font(Theme.display(64))
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onChange(of: text) { _, _ in issues = []; confirming = false; saveError = nil }
                    .accessibilityLabel("Weight in pounds")
                Text("lbs").font(Theme.display(24)).foregroundStyle(Theme.gray)
            }
            .padding(.vertical, 10).padding(.horizontal, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))

            if when == .after, let before = todaysBefore {
                Text("Before practice today: \(before.weight.lbs) lbs")
                    .font(.footnote).foregroundStyle(Theme.gray)
            } else if let last = history.first(where: { $0.isAfterPractice == (when == .after) }) {
                Text("Last \(when == .after ? "after practice" : "weigh-in"): \(last.weight.lbs) lbs on \(last.date.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.footnote).foregroundStyle(Theme.gray)
            }

            ForEach(issues, id: \.text) { issue in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: issue.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issue.isBlocking ? Theme.red : Theme.gold)
                    Text(issue.text).font(.subheadline)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(issue.isBlocking ? Theme.noBG : Theme.gold.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            }
            if let saveError {
                Text(saveError).font(.subheadline).foregroundStyle(Theme.red)
            }

            Spacer()

            if confirming {
                Button { Task { await save() } } label: {
                    Text("Yes, Log \(WeighInCheck.parse(text)?.lbs ?? "") lbs").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.red).controlSize(.large).disabled(saving)
                Button("Let Me Fix It") { confirming = false; issues = []; focused = true }
            } else {
                Button { check() } label: {
                    HStack { if saving { ProgressView().tint(.white) }; Text("Save Weigh-In") }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.red).controlSize(.large)
                .disabled(text.isEmpty || saving)
            }
            Text(wrestler == nil ? "Self-reported. This doesn't replace official weigh-ins." : "This goes on the team sheet as a coach weigh-in for \(wrestler!.name).")
                .font(.caption).foregroundStyle(Theme.gray)
        }
    }

    /// The weigh-ins this entry is checked against, newest first.
    private var history: [WeighIn] {
        guard let w = wrestler else { return store.weighIns }
        return store.weighIns(for: w.name)?.sorted ?? []
    }
    private var plan: DescentPlan? { wrestler.map { store.plan(for: $0.name) } ?? store.portal?.descent }
    private var firstName: String { wrestler.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name } ?? "" }

    private var todaysBefore: WeighIn? {
        history.first { $0.kind == .before && Calendar.current.isDateInToday($0.date) }
    }

    private func check() {
        let w = WeighInCheck.parse(text)
        issues = WeighInCheck.issues(for: w, when: when, history: history, plan: plan, coach: wrestler != nil)
        if issues.contains(where: \.isBlocking) { return }
        if issues.isEmpty { Task { await save() } } else { confirming = true; focused = false }
    }

    private func save() async {
        guard let w = WeighInCheck.parse(text) else { return }
        saving = true
        defer { saving = false }
        do {
            if let target = wrestler {
                saved = try await store.coachLogWeight(name: target.name, email: target.email, weight: w, when: when)
            } else {
                try await store.logWeight(w, when: when)
                saved = store.latest
            }
        } catch {
            saveError = error.localizedDescription
            confirming = false
        }
    }
}

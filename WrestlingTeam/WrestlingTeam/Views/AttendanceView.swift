import SwiftUI

/// One wrestler's mark. The sheet only knows Present / Absent (the Dashboard counts exactly those words),
/// so Late saves as Present and Excused as Absent; who was late or excused goes on a line in Notes.
enum AttendanceMark: String, CaseIterable {
    case here, late, excused, absent
    var sheetValue: String { self == .here || self == .late ? "Present" : "Absent" }
    var badge: String { switch self { case .here: "HERE"; case .late: "LATE"; case .excused: "EXCUSED"; case .absent: "—" } }
    var counted: Bool { self == .here || self == .late }
}

/// Splits "Late: A, B" / "Excused: C" lines out of the saved notes and puts them back.
enum AttendanceNotes {
    static let latePrefix = "Late: ", excusedPrefix = "Excused: "

    static func parse(_ notes: String) -> (text: String, late: Set<String>, excused: Set<String>) {
        var late = Set<String>(), excused = Set<String>(), keep: [String] = []
        for line in notes.components(separatedBy: "\n") {
            if line.hasPrefix(latePrefix) { late.formUnion(names(line.dropFirst(latePrefix.count))) }
            else if line.hasPrefix(excusedPrefix) { excused.formUnion(names(line.dropFirst(excusedPrefix.count))) }
            else { keep.append(line) }
        }
        return (keep.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), late, excused)
    }

    static func build(text: String, late: [String], excused: [String]) -> String {
        var lines: [String] = []
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { lines.append(t) }
        if !late.isEmpty { lines.append(latePrefix + late.joined(separator: ", ")) }
        if !excused.isEmpty { lines.append(excusedPrefix + excused.joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }

    private static func names(_ s: Substring) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// Coaches: the portal's "Take Attendance" tab. Pick the kind and date, tap who's here, save.
/// Saving the same kind + date again edits that entry (nothing gets double counted), same as the website.
struct AttendanceView: View {
    @EnvironmentObject var store: PortalStore
    @Environment(\.horizontalSizeClass) private var hsc

    @State private var kind: AttendanceKind = .practice
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var session: AttendanceSession?
    @State private var marks: [String: AttendanceMark] = [:]
    @State private var savedMarks: [String: AttendanceMark] = [:]
    @State private var notes = ""
    @State private var savedNotes = ""
    @State private var loading = false
    /// Refreshing a session that's already on screen (from the cache) — small spinner only.
    @State private var refreshing = false
    @State private var loadError: String?
    @State private var saving = false
    @State private var toast: (text: String, ok: Bool)?
    /// A kind/date change waiting on "discard unsaved changes?".
    @State private var pending: (kind: AttendanceKind, date: Date)?

    private var dateKey: String { DayKey.key(date) }
    private var dirty: Bool { session != nil && (marks != savedMarks || notes != savedNotes) }
    private var hereCount: Int { (session?.names ?? []).filter { mark($0).counted }.count }
    private func mark(_ n: String) -> AttendanceMark { marks[n] ?? .absent }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    pickers
                    if loading && session == nil {
                        ProgressView("Loading roster…").padding(.vertical, 40)
                    } else if let e = loadError {
                        Card(title: "Couldn't load") {
                            Text(e).foregroundStyle(Theme.gray)
                            Button("Try Again") { Task { await load() } }.buttonStyle(.borderedProminent).tint(Theme.red)
                        }
                    } else if let s = session {
                        roster(s)
                    }
                }
                .padding()
                .readableWidth(900)
            }
            .onChange(of: toast?.text) { _, t in
                if t != nil { withAnimation { proxy.scrollTo("toast", anchor: .center) } }
            }
            }
            .screenBackground()
            .refreshable { if !dirty { await load() } }
            .navigationTitle("Take Attendance")
            .teamLogo()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        if refreshing || (loading && session != nil) { ProgressView().controlSize(.small) }
                        if dirty { Text("Unsaved").font(.caption.bold()).foregroundStyle(Theme.red) }
                    }
                }
            }
        }
        .task { if session == nil { await load() } }
        .alert("Discard unsaved attendance?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Discard", role: .destructive) {
                if let p = pending { kind = p.kind; date = p.date; pending = nil; Task { await load() } }
            }
            Button("Keep Editing", role: .cancel) { pending = nil }
        } message: {
            Text("You marked wrestlers for \(kind.label) on \(DayKey.pretty(dateKey)) but haven't saved.")
        }
    }

    // MARK: Kind, date, recent dates

    private var pickers: some View {
        let kindBinding = Binding(get: { kind }, set: { change(kind: $0, date: date) })
        return Card {
            if hsc == .regular {
                Picker("Type", selection: kindBinding) {
                    ForEach(AttendanceKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } else {
                // Five kinds don't fit a segmented control on iPhone.
                HStack {
                    Text("Type").font(.subheadline.bold())
                    Spacer()
                    Picker("Type", selection: kindBinding) {
                        ForEach(AttendanceKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu).tint(Theme.ink)
                }
            }

            DatePicker("Date", selection: Binding(get: { date }, set: { change(kind: kind, date: Calendar.current.startOfDay(for: $0)) }),
                       displayedComponents: .date)
                .font(.subheadline.bold())

            if let recent = session?.recent, !recent.isEmpty {
                if hsc == .regular {
                    // iPad: wrap the chips instead of running them off the edge.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent").font(.caption).foregroundStyle(Theme.gray)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(recent.prefix(12), id: \.self) { recentChip($0) }
                        }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Text("Recent:").font(.caption).foregroundStyle(Theme.gray)
                            ForEach(recent, id: \.self) { recentChip($0) }
                        }
                    }
                }
            }
        }
    }

    private func recentChip(_ k: String) -> some View {
        Button {
            if let d = DayKey.date(k) { change(kind: kind, date: d) }
        } label: {
            Text(DayKey.pretty(k)).font(.caption.bold()).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: hsc == .regular ? .infinity : nil)
                .foregroundStyle(k == dateKey ? Theme.card : Theme.ink)
                .background(k == dateKey ? Theme.ink : Theme.soft, in: Capsule())
        }
    }

    private func change(kind newKind: AttendanceKind, date newDate: Date) {
        guard newKind != kind || DayKey.key(newDate) != dateKey else { return }
        if dirty { pending = (newKind, newDate); return }
        kind = newKind; date = newDate
        Task { await load() }
    }

    // MARK: Roster

    @ViewBuilder private func roster(_ s: AttendanceSession) -> some View {
        let editing = s.exists
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: editing ? "pencil.circle.fill" : "plus.circle.fill")
                .foregroundStyle(editing ? Theme.goldText : Theme.ok)
            (Text(editing ? "Editing " : "New ").bold()
             + Text(editing
                    ? "the \(kind.label) already saved for \(DayKey.pretty(s.date)). Saving replaces that entry, nothing gets double counted."
                    : "\(kind.label) for \(DayKey.pretty(s.date)). Tap each wrestler who is here.")
             + Text(kind.tracksOnly ? " Tracked only, no Ironman points." : ""))
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(editing ? Theme.gold.opacity(0.18) : Theme.okBG, in: RoundedRectangle(cornerRadius: 12))

        Card {
            HStack {
                Button("Everyone here") { setAll(.here) }.buttonStyle(.bordered)
                Button("Clear all") { setAll(.absent) }.buttonStyle(.bordered)
                Spacer()
                Text("\(hereCount) / \(s.names.count) here").font(.subheadline.bold()).monospacedDigit()
            }
            .tint(Theme.ink)

            if s.names.isEmpty {
                Text("No wrestlers on the Dashboard yet.").foregroundStyle(Theme.gray)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(s.names, id: \.self) { name in markButton(name) }
            }
            Text("Tap to mark here. Press and hold a name for Late or Excused.")
                .font(.caption).foregroundStyle(Theme.gray)

            TextField("Notes (optional), e.g. who left early", text: $notes, axis: .vertical)
                .lineLimit(2...5)
                .padding(10)
                .background(Theme.soft, in: RoundedRectangle(cornerRadius: 10))

            Button {
                Task { await save() }
            } label: {
                HStack {
                    if saving { ProgressView().tint(.white) }
                    Text(saving ? "Saving…" : "Save Attendance").bold()
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent).tint(Theme.red)
            .disabled(saving || s.names.isEmpty)

            Text("Anyone not tapped is saved as Absent. Late counts as Present and Excused as Absent; both are listed in the notes.")
                .font(.caption).foregroundStyle(Theme.gray)

            if let t = toast {
                Text(t.text).font(.subheadline)
                    .foregroundStyle(t.ok ? Theme.ok : Theme.red)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(t.ok ? Theme.okBG : Theme.noBG, in: RoundedRectangle(cornerRadius: 10))
                    .id("toast")
            }
        }
    }

    private func markButton(_ name: String) -> some View {
        let m = mark(name)
        let fill: Color = switch m { case .here: Theme.ok; case .late: Theme.gold; case .excused: Theme.gray; case .absent: Theme.card }
        let text: Color = m == .absent ? Theme.ink : m == .late ? Theme.heroInk : .white
        return Button {
            set(name, m == .absent ? .here : .absent)
        } label: {
            HStack {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Text(m.badge).font(.caption.bold())
            }
            .padding(.horizontal, 12).frame(minHeight: 48)
            .foregroundStyle(text)
            .background(fill, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(m == .absent ? Theme.line : fill))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { set(name, .here) } label: { Label("Here", systemImage: "checkmark.circle") }
            Button { set(name, .late) } label: { Label("Late", systemImage: "clock") }
            Button { set(name, .excused) } label: { Label("Excused", systemImage: "hand.raised") }
            Button { set(name, .absent) } label: { Label("Absent", systemImage: "xmark.circle") }
        }
        .accessibilityLabel("\(name), \(m == .absent ? "not here" : m.rawValue)")
        .accessibilityAddTraits(m.counted ? .isSelected : [])
    }

    private func set(_ name: String, _ m: AttendanceMark) { marks[name] = m; toast = nil }

    private func setAll(_ m: AttendanceMark) {
        for n in session?.names ?? [] { marks[n] = m }
        toast = nil
    }

    // MARK: Load / save

    private static func cacheKey(_ k: AttendanceKind, _ d: String) -> String { k.rawValue + "|" + d }

    /// Shows a cached copy right away (if any), then gets the latest from the sheet and preloads likely next picks.
    private func load() async {
        loadError = nil; toast = nil
        let k = kind, d = dateKey
        if let cached = store.attendanceCache[Self.cacheKey(k, d)] {
            apply(cached)
            refreshing = true
        } else {
            loading = true
        }
        defer { loading = false; refreshing = false }
        do {
            var s = try await store.api.attendance(kind: k, date: d)
            s.names = s.names.sortedByLastName { $0 }
            store.attendanceCache[Self.cacheKey(k, d)] = s
            guard k == kind, d == dateKey else { return }   // the coach switched again while this loaded
            if !dirty { apply(s) }                           // never wipe taps made while it was refreshing
            prefetch(around: k, date: d, recent: s.recent)
        } catch {
            if session == nil || store.attendanceCache[Self.cacheKey(k, d)] == nil { loadError = error.localizedDescription }
        }
    }

    private func apply(_ s: AttendanceSession) {
        let parsed = AttendanceNotes.parse(s.notes)
        var m: [String: AttendanceMark] = [:]
        for n in s.names {
            let present = s.marks[n] == "Present"
            m[n] = parsed.late.contains(n) && present ? .late
                 : parsed.excused.contains(n) && !present ? .excused
                 : present ? .here : .absent
        }
        session = s
        marks = m; savedMarks = m
        notes = parsed.text; savedNotes = parsed.text
    }

    /// Quietly loads the other types for this date and the last few dates of this type, so tapping them is instant.
    private func prefetch(around k: AttendanceKind, date d: String, recent: [String]) {
        var want = AttendanceKind.allCases.filter { $0 != k }.map { ($0, d) }
        want += recent.filter { $0 != d }.prefix(3).map { (k, $0) }
        let missing = want.filter { store.attendanceCache[Self.cacheKey($0.0, $0.1)] == nil }
        guard !missing.isEmpty else { return }
        let api = store.api
        Task {
            await withTaskGroup(of: (String, AttendanceSession?).self) { group in
                for (kk, dd) in missing {
                    group.addTask { (Self.cacheKey(kk, dd), try? await api.attendance(kind: kk, date: dd)) }
                }
                for await (key, s) in group {
                    if var s { s.names = s.names.sortedByLastName { $0 }; store.attendanceCache[key] = s }
                }
            }
        }
    }

    private func save() async {
        guard let s = session else { return }
        saving = true
        defer { saving = false }
        let payload = Dictionary(uniqueKeysWithValues: s.names.map { ($0, mark($0).sheetValue) })
        let fullNotes = AttendanceNotes.build(text: notes,
                                              late: s.names.filter { mark($0) == .late },
                                              excused: s.names.filter { mark($0) == .excused })
        do {
            let r = try await store.api.saveAttendance(kind: kind, date: s.date, marks: payload, notes: fullNotes)
            savedMarks = marks; savedNotes = notes
            session?.exists = true
            session?.notes = fullNotes
            if !(session?.recent.contains(r.date) ?? true) {
                session?.recent.append(r.date)
                session?.recent.sort(by: >)
            }
            if var cached = session {
                cached.marks = payload; cached.notes = fullNotes
                store.attendanceCache[Self.cacheKey(kind, s.date)] = cached
            }
            toast = ("Saved: \(r.present) of \(r.total) here for \(r.label) on \(DayKey.pretty(r.date)). Dashboard updated.", true)
            Task { await store.load() }   // refresh the Team tab's points in the background; don't make the coach wait
        } catch {
            toast = ("Not saved: \(error.localizedDescription)", false)
        }
    }
}

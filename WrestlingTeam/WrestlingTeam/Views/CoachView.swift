import SwiftUI

/// Coaches get their own tabs: Team (Ironman), Weigh-Ins, Descent Plans, Handbook.
/// Tapping a wrestler anywhere opens their page with stats, weigh-in chart and history.
struct CoachTabs: View {
    @EnvironmentObject var store: PortalStore
    @State private var tab: String = {
        #if DEBUG
        if let t = UserDefaults.standard.string(forKey: "CoachTab") { return t }   // -CoachTab weighins (screenshots)
        #endif
        return "team"
    }()

    private var hasDescent: Bool { !(store.portal?.descents ?? []).isEmpty }
    @Environment(\.horizontalSizeClass) private var hsc

    var body: some View {
        // Five tabs don't fit iPadOS's floating top tab bar on smaller iPads (Handbook got hidden behind an arrow and
        // the bar covered list titles). Giving the TabView a compact size class keeps the normal bottom tab bar on
        // iPad too; each tab gets the real size class back so the iPad split view (list + wrestler page) still works.
        TabView(selection: $tab) {
            CoachTeamView().environment(\.horizontalSizeClass, hsc)
                .tabItem { Label("Team", systemImage: "person.3.fill") }.tag("team")
            AttendanceView().environment(\.horizontalSizeClass, hsc)
                .tabItem { Label("Attendance", systemImage: "checklist") }.tag("attendance")
            CoachWeighInsView().environment(\.horizontalSizeClass, hsc)
                .tabItem { Label("Weigh-Ins", systemImage: "scalemass.fill") }.tag("weighins")
            if hasDescent {
                CoachDescentView().environment(\.horizontalSizeClass, hsc)
                    .tabItem { Label("Descent", systemImage: "chart.line.downtrend.xyaxis") }.tag("descent")
            }
            CoachHandbookView().environment(\.horizontalSizeClass, hsc)
                .tabItem { Label("Handbook", systemImage: "book.closed.fill") }.tag("handbook")
        }
        .environment(\.horizontalSizeClass, .compact)
        .task { await store.loadCoachData() }
    }
}

/// Sign-out menu shared by the coach tabs.
private struct CoachAccountMenu: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var store: PortalStore
    var body: some View {
        Menu {
            if let email = store.portal?.email { Text("Signed in as \(email)") }
            Button("Sign Out", role: .destructive) { auth.signOut() }
        } label: { Image(systemName: "person.crop.circle") }
    }
}

/// Coach list + wrestler page. iPhone: tap a row to push the wrestler's page.
/// iPad (regular width): split view, list on the left, the selected row's page on the right.
/// With an `overview`, the right side shows it until a wrestler is picked (Team tab); otherwise the first
/// wrestler in the list (`first`) opens automatically so the right side is never blank.
struct WrestlerBrowser<Rows: View>: View {
    static var overviewTag: String { "__overview__" }

    @EnvironmentObject var store: PortalStore
    var title: String
    var initial: String? = nil
    var first: String? = nil
    var search: Binding<String>? = nil
    /// Descent tab: tapping a name goes straight to that wrestler's plan instead of their full page.
    var opensPlan = false
    var overview: AnyView? = nil
    var refresh: () async -> Void
    @ViewBuilder var rows: () -> Rows

    @Environment(\.horizontalSizeClass) private var hsc
    @State private var selected: String?
    @State private var path: [String] = []

    var body: some View {
        if hsc == .regular {
            NavigationSplitView {
                configured(List(selection: $selected) { rows() })
                    .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
            } detail: {
                NavigationStack {
                    if let s = selected, s != Self.overviewTag {
                        destination(store.resolveName(s)).id(s)
                    } else if let overview {
                        overview
                    } else {
                        ContentUnavailableView("Choose a wrestler", systemImage: opensPlan ? "chart.line.downtrend.xyaxis" : "person.crop.circle",
                                               description: Text(opensPlan ? "Pick someone from the list to see their descent plan."
                                                                            : "Pick someone from the list to see their stats, weigh-ins and chart."))
                    }
                }
            }
            .onAppear { if selected == nil { selected = initial ?? (overview != nil ? Self.overviewTag : first) } }
            .onChange(of: first) { _, f in if selected == nil, overview == nil { selected = f } }
        } else {
            NavigationStack(path: $path) {
                configured(List { rows() })
                    .navigationDestination(for: String.self) { destination(store.resolveName($0)) }
            }
            .onAppear { if path.isEmpty, let i = initial { path = [i] } }
        }
    }

    @ViewBuilder private func destination(_ name: String) -> some View {
        if opensPlan { CoachPlanView(name: name) } else { WrestlerDetailView(name: name) }
    }

    @ViewBuilder private func configured<L: View>(_ list: L) -> some View {
        let v = list
            .refreshable { await refresh() }
            .navigationTitle(title)
            .teamLogo()
            .toolbar { CoachAccountMenu() }
        if let search { v.searchable(text: search, prompt: "Find a wrestler") } else { v }
    }
}

// MARK: - Team (Ironman)

/// Team snapshot keys, in the website portal's order; anything else after.
private func snapshotKeys(_ t: LooseDict) -> [String] {
    let order = ["Wrestlers Tracked", "Practice Sessions", "Open Mat Sessions", powerSessionsKey, "Current Ironmen", "Team Practice %"]
    return order.filter { t[$0] != nil } + t.values.keys.filter { !order.contains($0) }.sorted()
}

struct CoachTeamView: View {
    @EnvironmentObject var store: PortalStore
    @Environment(\.horizontalSizeClass) private var hsc
    @State private var search = ""

    var body: some View {
        WrestlerBrowser(title: "Team", search: $search, overview: AnyView(CoachTeamOverview()), refresh: { await store.refreshAll() }) {
                if hsc == .regular {
                    // iPad: the snapshot lives in the Team Overview page on the right (pinned, doesn't scroll away).
                    Section {
                        Label("Team Overview", systemImage: "chart.bar.fill").bold()
                            .tag(WrestlerBrowser<EmptyView>.overviewTag)
                    }
                } else if let team = store.portal?.team, !team.values.isEmpty {
                    Section("Team Snapshot") {
                        ForEach(snapshotKeys(team), id: \.self) { k in
                            HStack { Text(k); Spacer(); Text(team[k] ?? "").bold() }
                                .selectionDisabled()
                        }
                    }
                }
                Section("Wrestlers") {
                    ForEach(rows) { r in
                        NavigationLink(value: r.name) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(r.name).bold()
                                        if let wc = store.weightClass(for: r.name) {
                                            Tag(text: wc.cls, color: wc.source == .coach ? Theme.red : Theme.gray)
                                        }
                                    }
                                    Text(caption(r)).font(.caption).foregroundStyle(Theme.gray)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(r.total.isEmpty ? "0" : r.total).font(Theme.display(22))
                                    StatusBadge(status: r.status, compact: true)
                                }
                            }
                        }
                        .tag(r.name)
                    }
                }
                if let updated = store.portal?.updated {
                    Section { Text("Updated \(updated)").font(.caption).foregroundStyle(Theme.gray) }
                }
        }
    }

    private func caption(_ r: IronmanStats) -> String {
        var s = r.pct.isEmpty ? "No practices yet" : "\(r.pct) practice · \(r.absent.isEmpty ? "0" : r.absent) absent"
        if store.portal?.team?[powerSessionsKey] != nil, let m = number(r.power), m > 0 { s += " · \(m.lbs) P/S" }
        return s
    }

    private var rows: [IronmanStats] {
        let all = (store.portal?.wrestlers ?? []).sortedByLastName(\.name)
        return search.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
}

/// iPad Team tab, right side: the team snapshot plus who needs attention today.
struct CoachTeamOverview: View {
    @EnvironmentObject var store: PortalStore

    var body: some View {
        let team = store.portal?.team ?? LooseDict()
        let wrestlers = (store.portal?.wrestlers ?? []).sortedByLastName(\.name)
        let offTrack = wrestlers.filter { StatusTone($0.status) == .bad }
        let weighedToday = store.team.filter { w in w.weighIns.contains { Calendar.current.isDateInToday($0.date) } }
        let over = wrestlers.map(\.name).filter { store.isWellOverPlan($0) }

        ScrollView {
            VStack(spacing: 14) {
                Hero(eyebrow: AppConfig.teamName, title: "Team Overview",
                     subtitle: AnyView(Text(store.portal?.updated.map { "Updated \($0)" } ?? "").font(.caption).foregroundStyle(Theme.lightText))) {
                    BigNumber(value: team["Current Ironmen"] ?? "0", label: "Current Ironmen")
                }
                AdaptiveGrid(compact: 3, regular: 5) {
                    ForEach(snapshotKeys(team).filter { $0 != "Current Ironmen" }, id: \.self) { k in
                        Tile(value: team[k] ?? "", label: k)
                    }
                }
                Card(title: "Weigh-ins today") {
                    Text("\(weighedToday.count) of \(store.team.count) wrestlers have logged a weight today.")
                        .font(.subheadline).foregroundStyle(Theme.gray)
                    if !over.isEmpty {
                        Text("More than 5 lbs over this week's plan weight: " + over.joined(separator: ", "))
                            .font(.subheadline.bold()).foregroundStyle(Theme.red)
                    }
                }
                Card(title: "Off track (\(offTrack.count))") {
                    if offTrack.isEmpty {
                        Text("Everyone is on track.").foregroundStyle(Theme.gray)
                    }
                    ForEach(offTrack) { r in
                        NavigationLink { WrestlerDetailView(name: r.name) } label: {
                            HStack {
                                Text(r.name).bold()
                                Spacer()
                                Text(r.pct.isEmpty ? "—" : "\(r.pct) · \(r.absent) absent").font(.caption).foregroundStyle(Theme.gray)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.gray)
                            }
                        }
                        .foregroundStyle(Theme.ink)
                    }
                }
                if let h = store.handbook, !h.missing.isEmpty {
                    Card(title: "Handbook") {
                        Text("\(h.missing.count) haven't signed: " + h.missing.sortedByLastName { $0 }.joined(separator: ", "))
                            .font(.subheadline).foregroundStyle(Theme.gray)
                    }
                }
            }
            .padding()
            .readableWidth(900)
        }
        .screenBackground()
        .refreshable { await store.refreshAll() }
        .navigationTitle("Team Overview")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Weigh-Ins

enum WeighInFilter: String, CaseIterable, Identifiable {
    case all = "All", today = "Today", week = "This Week", over = "5+ Over"
    var id: String { rawValue }
}

struct CoachWeighInsView: View {
    @EnvironmentObject var store: PortalStore
    @State private var search = ""
    @State private var filter: WeighInFilter = .all
    @State private var path: [String] = {
        #if DEBUG
        if let n = UserDefaults.standard.string(forKey: "OpenWrestler") { return [n] }   // -OpenWrestler "Name" (screenshots)
        #endif
        return []
    }()

    var body: some View {
        WrestlerBrowser(title: "Weigh-Ins", initial: path.first, first: groups.first?.rows.first?.name, search: $search,
                        refresh: { await store.loadTeam() }) {
                Section {
                    Picker("Show", selection: $filter) {
                        ForEach(WeighInFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .selectionDisabled()
                }
                if let err = store.teamError, store.team.isEmpty {
                    Section { Text(err).foregroundStyle(Theme.red) }
                } else if store.team.isEmpty {
                    Section { HStack { ProgressView(); Text("Loading weigh-ins…").foregroundStyle(Theme.gray) } }
                }
                ForEach(groups, id: \.title) { g in
                    Section {
                        if g.rows.isEmpty {
                            Text(g.empty).foregroundStyle(Theme.gray).selectionDisabled()
                        }
                        ForEach(g.rows) { w in
                            NavigationLink(value: w.name) {
                                if w.latest != nil { WeighInRow(w: w, plan: store.plan(for: w.name)) }
                                else { Text(w.name).foregroundStyle(Theme.gray) }
                            }
                            .tag(w.name)
                        }
                    } header: { Text("\(g.title) (\(g.rows.count))") } footer: {
                        if let f = g.footer { Text(f) }
                    }
                }
        }
    }

    private struct Group { var title: String; var empty: String; var footer: String?; var rows: [WrestlerWeighIns] }

    private var groups: [Group] {
        let all = (search.isEmpty ? store.team : store.team.filter { $0.name.localizedCaseInsensitiveContains(search) })
            .sortedByLastName(\.name)
        guard !store.team.isEmpty else { return [] }
        let cal = Calendar.current
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date())!
        func logged(_ w: WrestlerWeighIns, since d: Date?) -> Bool {
            guard let d else { return w.latest != nil }
            return w.weighIns.contains { $0.date >= d }
        }
        let rowNote = "Each row shows the last before-practice weight and what was lost at that practice. Arrows compare with the previous before-practice weight. Self-reported."
        switch filter {
        case .all:
            return [Group(title: "Logged", empty: "No one has logged a weight yet.", footer: rowNote, rows: all.filter { logged($0, since: nil) }),
                    Group(title: "No weigh-ins yet", empty: "Everyone has logged at least once.", footer: nil, rows: all.filter { !logged($0, since: nil) })]
        case .today:
            let start = cal.startOfDay(for: Date())
            return [Group(title: "Not yet today", empty: "Everyone has weighed in today.", footer: nil, rows: all.filter { !logged($0, since: start) }),
                    Group(title: "Weighed in today", empty: "No one has weighed in today.", footer: rowNote, rows: all.filter { logged($0, since: start) })]
        case .week:
            return [Group(title: "Not in the last 7 days", empty: "Everyone has weighed in this week.", footer: nil, rows: all.filter { !logged($0, since: weekAgo) }),
                    Group(title: "Weighed in the last 7 days", empty: "No one has weighed in this week.", footer: rowNote, rows: all.filter { logged($0, since: weekAgo) })]
        case .over:
            let over = all.filter { store.isWellOverPlan($0.name) }
            return [Group(title: "5+ lbs over this week's plan", empty: "No one is more than 5 lbs over their plan weight.",
                          footer: "Latest before-practice weight is more than 5 lbs over this week's weight on their Descent Plans row.",
                          rows: over)]
        }
    }
}

private struct WeighInRow: View {
    var w: WrestlerWeighIns
    var plan: DescentPlan?

    /// Lead with the before-practice weight (what the plan compares); show that day's practice loss next to it.
    private var shown: WeighIn { w.weighIns.latestForPlan ?? w.latest! }
    private var practiceLoss: Double? {
        let cal = Calendar.current
        guard let after = w.sorted.first(where: { $0.isAfterPractice && cal.isDate($0.date, inSameDayAs: shown.date) && $0.date > shown.date })
        else { return nil }
        return w.weighIns.practiceLoss(for: after)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(w.name).bold()
                HStack(spacing: 6) {
                    Text(shown.date.shortAgo + (shown.kind.map { " · " + $0.short } ?? ""))
                    if let step = thisWeek, !shown.isAfterPractice {
                        let diff = shown.weight - step.weight
                        Text("· \(diff >= 0 ? "+" : "−")\(abs(diff).lbs) vs plan")
                            .foregroundStyle(diff > PortalStore.overPlanFlag ? Theme.red : Theme.gray)
                            .fontWeight(diff > PortalStore.overPlanFlag ? .bold : .regular)
                    }
                }
                .font(.caption).foregroundStyle(Theme.gray)
                .lineLimit(1).minimumScaleFactor(0.85)
                if let loss = practiceLoss {
                    Text("\(loss >= 0 ? "−" : "+")\(abs(loss).lbs) lbs at practice").font(.caption.weight(.semibold)).foregroundStyle(Theme.goldText)
                }
            }
            Spacer()
            if let prev = w.weighIns.previous(sameKindAs: shown) {
                let d = shown.weight - prev.weight
                Image(systemName: d < 0 ? "arrow.down.right" : d > 0 ? "arrow.up.right" : "arrow.right")
                    .font(.caption.bold()).foregroundStyle(Theme.gray)
            }
            Text(shown.weight.lbs).font(Theme.display(24)).frame(minWidth: 64, alignment: .trailing)
        }
    }

    private var thisWeek: DescentStep? {
        guard let p = plan, p.currentIndex() >= 0 else { return nil }
        return p.currentStep
    }
}

// MARK: - Descent plans

struct CoachDescentView: View {
    @EnvironmentObject var store: PortalStore

    private var plans: [DescentPlan] { (store.portal?.descents ?? []).sortedByLastName(\.name) }

    var body: some View {
        WrestlerBrowser(title: "Descent Plans", first: plans.first?.name, opensPlan: true, refresh: { await store.refreshAll() }) {
                Section {
                    ForEach(plans, id: \.email) { p in
                        NavigationLink(value: p.name) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.name).bold()
                                    if let g = store.planGap(for: p.name) {
                                        Text("Last \(g.weight.lbs) · " + (g.gap >= 0 ? "\(g.gap.lbs) over" : "\((-g.gap).lbs) under"))
                                            .font(.caption.weight(.semibold)).foregroundStyle(g.gap > PortalStore.overPlanFlag ? Theme.red : Theme.ink)
                                    } else {
                                        Text("No before-practice weigh-in yet").font(.caption).foregroundStyle(Theme.gray)
                                    }
                                    Text("Lowest class \(p.minClass) · min \(number(p.minWeight)?.lbs ?? p.minWeight)")
                                        .font(.caption).foregroundStyle(Theme.gray)
                                }
                                Spacer()
                                if let s = p.currentStep {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(s.weight.lbs).font(Theme.display(22))
                                        Text(p.currentIndex() >= 0 ? "this week" : "starts").font(.caption2).foregroundStyle(Theme.gray)
                                    }
                                }
                            }
                        }
                        .tag(p.name)
                    }
                } footer: {
                    Text("Right: this week's plan weight from the Descent Plans tab. \"Last\" is the latest before-practice weigh-in; red means more than 5 lbs over.")
                }
        }
    }
}

// MARK: - Handbook

struct CoachHandbookView: View {
    @EnvironmentObject var store: PortalStore
    @State private var copied = false

    /// Just the sign-off list: who has and hasn't signed, with the handbook link on top. No wrestler pages here.
    var body: some View {
        NavigationStack {
            List {
                if let h = store.handbook {
                    let total = h.signed.count + h.missing.count
                    let missing = h.missing.sortedByLastName { $0 }
                    let emails = missing.compactMap { store.email(for: $0) }
                    Section {
                        if let url = URL(string: h.url) {
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "book.closed.fill")
                                    Text("Open the \(h.season) Team Handbook").bold()
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .foregroundStyle(.white)
                                .padding(.vertical, 6)
                            }
                            .listRowBackground(Theme.red)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(h.signed.count) of \(total) signed").font(Theme.display(26))
                            ProgressView(value: Double(h.signed.count), total: Double(max(total, 1))).tint(Theme.ok)
                        }
                        .padding(.vertical, 4)
                    }
                    Section {
                        if missing.isEmpty { Text("Everyone has signed.").foregroundStyle(Theme.gray) }
                        ForEach(missing, id: \.self) { n in
                            Label(n, systemImage: "exclamationmark.circle").foregroundStyle(Theme.red)
                        }
                        if !emails.isEmpty {
                            HStack(spacing: 12) {
                                Button {
                                    UIPasteboard.general.string = emails.joined(separator: ", ")
                                    copied = true
                                } label: {
                                    Label(copied ? "Copied \(emails.count) emails" : "Copy their emails", systemImage: copied ? "checkmark" : "doc.on.doc")
                                }
                                .buttonStyle(.bordered).tint(Theme.ink)
                                if let mail = reminderURL(emails, season: h.season, link: h.url) {
                                    Link(destination: mail) { Label("Email reminder", systemImage: "envelope").foregroundStyle(.white) }
                                        .buttonStyle(.borderedProminent).tint(Theme.red)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: { Text("Not signed yet (\(missing.count))") } footer: {
                        if !emails.isEmpty { Text("The reminder opens Mail with their school emails in BCC.") }
                    }
                    Section("Signed (\(h.signed.count))") {
                        if h.signed.isEmpty { Text("No one has signed yet.").foregroundStyle(Theme.gray) }
                        ForEach(h.signed.sortedByLastName(\.name), id: \.name) { s in
                            HStack {
                                Label(s.name, systemImage: "checkmark.seal.fill").foregroundStyle(Theme.ink)
                                Spacer()
                                Text(s.when).font(.caption).foregroundStyle(Theme.gray)
                            }
                        }
                    }
                } else if let err = store.handbookError {
                    Section { Text(err).foregroundStyle(Theme.red) }
                } else {
                    Section { HStack { ProgressView(); Text("Loading…").foregroundStyle(Theme.gray) } }
                }
            }
            .refreshable { copied = false; await store.loadCoachData() }
            .navigationTitle("Handbook")
            .teamLogo()
            .toolbar { CoachAccountMenu() }
        }
    }

    private func reminderURL(_ emails: [String], season: String, link: String) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.queryItems = [
            URLQueryItem(name: "bcc", value: emails.joined(separator: ",")),
            URLQueryItem(name: "subject", value: "Reminder: sign the \(season) wrestling handbook"),
            URLQueryItem(name: "body", value: "Please read the team handbook and sign off in the \(AppConfig.teamName) app (Handbook tab) or on the portal.\n\nHandbook: \(link)"),
        ]
        return c.url
    }
}

/// Descent tab destination: one wrestler's plan, with a link to the rest of their page.
struct CoachPlanView: View {
    @EnvironmentObject var store: PortalStore
    var name: String

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let p = store.plan(for: name), !p.steps.isEmpty {
                    DescentPlanContent(plan: p, notes: store.portal?.descentNotes ?? LooseDict(),
                                       latest: store.weighIns(for: name)?.weighIns.latestForPlan, forCoach: true)
                } else {
                    ContentUnavailableView("No descent plan", systemImage: "chart.line.downtrend.xyaxis",
                                           description: Text("\(name) isn't on the Descent Plans tab."))
                }
                NavigationLink { WrestlerDetailView(name: name) } label: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                        Text("Stats & weigh-ins for \(name)")
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.gray)
                    }
                    .font(.subheadline).padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                }
                .foregroundStyle(Theme.ink)
            }
            .padding()
            .readableWidth(900)
        }
        .screenBackground()
        .refreshable { await store.refreshAll() }
        .navigationTitle("\(name)'s Descent Plan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - One wrestler

/// A coach's page for one wrestler: Ironman stats, weigh-in chart (with descent plan line), history, descent plan.
struct WrestlerDetailView: View {
    @EnvironmentObject var store: PortalStore
    var name: String
    @State private var logging = false
    @State private var fixing: WeighIn?
    @State private var pickingClass = false

    var body: some View {
        let stats = store.stats(for: name)
        let weighIns = store.weighIns(for: name)?.weighIns ?? []
        let plan = store.plan(for: name)
        let latest = weighIns.max { $0.date < $1.date }
        let dry = weighIns.latestForPlan

        ScrollView {
            VStack(spacing: 14) {
                Hero(eyebrow: "Wrestler", title: name,
                     subtitle: AnyView(VStack(alignment: .leading, spacing: 8) {
                         if let s = stats { StatusBadge(status: s.status) }
                         if let email = store.weighIns(for: name)?.email, !email.isEmpty {
                             Text(email).font(.caption).foregroundStyle(Theme.lightText)
                         }
                     })) {
                    BigNumber(value: stats?.total ?? "—", label: "Ironman Points")
                }

                if let s = stats {
                    AdaptiveGrid(compact: 3, regular: 6) {
                        Tile(value: s.present, label: "Practices Present")
                        Tile(value: s.absent, label: "Practices Absent")
                        Tile(value: s.pct, label: "Practice Attendance")
                        Tile(value: s.openmat, label: "Open Mats")
                        Tile(value: s.kids, label: "Kids Club Help")
                        Tile(value: s.youth, label: "Youth Tournament")
                    }
                }

                if let sessions = store.portal?.team?[powerSessionsKey] {
                    PowerSpeedCard(count: stats?.power ?? "", sessions: sessions, forCoach: true)
                }
                weightClassCard(plan: plan)
                lastWeighIn(latest: latest, all: weighIns, plan: plan)
                if let email = store.email(for: name) {
                    Button { logging = true } label: {
                        Label("Weigh In \(name.split(separator: " ").first.map(String.init) ?? name)", systemImage: "scalemass.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.red)
                }
                WeighInChart(entries: weighIns, plan: plan)
                if !weighIns.isEmpty {
                    WeighInHistory(entries: weighIns, onEdit: store.email(for: name) == nil ? nil : { fixing = $0 })
                }

                if let p = plan, !p.steps.isEmpty {
                    NavigationLink {
                        ScrollView {
                            DescentPlanContent(plan: p, notes: store.portal?.descentNotes ?? LooseDict(), latest: dry, forCoach: true)
                                .padding()
                        }
                        .screenBackground()
                        .navigationTitle("\(name.split(separator: " ").first.map(String.init) ?? name)'s Descent Plan")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack {
                            Image(systemName: "chart.line.downtrend.xyaxis")
                            Text("Full descent plan")
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.gray)
                        }
                        .font(.subheadline).padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
            .padding()
            .readableWidth(900)
        }
        .screenBackground()
        .refreshable { await store.loadTeam() }
        .sheet(isPresented: $logging) {
            if let email = store.email(for: name) { LogWeightView(wrestler: (name, email)).environmentObject(store) }
        }
        .sheet(isPresented: $pickingClass) {
            if let email = store.email(for: name) { WeightClassPicker(name: name, email: email).environmentObject(store) }
        }
        .background(EmptyView().sheet(item: $fixing) { entry in
            if let email = store.email(for: name) { EditWeighInView(name: name, email: email, entry: entry).environmentObject(store) }
        })
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func weightClassCard(plan: DescentPlan?) -> some View {
        let wc = store.weightClass(for: name)
        Card(title: "Weight Class") {
            HStack(alignment: .center, spacing: 14) {
                Text(wc?.cls ?? "—").font(Theme.display(40)).foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 3) {
                    if let wc, wc.source == .coach, let o = store.classOverride(for: name) {
                        Text("Set by a coach").font(.subheadline.bold())
                        Text(o.updated.isEmpty ? "Overrides the descent plan" : "\(o.updated) · overrides the descent plan")
                            .font(.caption).foregroundStyle(Theme.gray)
                    } else if wc != nil {
                        Text("From the descent plan").font(.subheadline.bold())
                        Text("This week's lowest eligible class").font(.caption).foregroundStyle(Theme.gray)
                    } else {
                        Text("Not set").font(.subheadline.bold())
                        Text("No descent plan yet").font(.caption).foregroundStyle(Theme.gray)
                    }
                }
                Spacer()
                if store.email(for: name) != nil {
                    Button("Change") { pickingClass = true }.buttonStyle(.bordered).tint(Theme.red)
                }
            }
        }
    }

    @ViewBuilder private func lastWeighIn(latest: WeighIn?, all: [WeighIn], plan: DescentPlan?) -> some View {
        Card(title: "Last Weigh-In") {
            if let last = latest {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(last.weight.lbs) lbs").font(Theme.display(30))
                    if let loss = all.practiceLoss(for: last) {
                        Text((loss >= 0 ? "−" : "+") + abs(loss).lbs + " at practice").font(.caption.bold()).foregroundStyle(Theme.goldText)
                    } else if let prev = all.previous(sameKindAs: last) { ChangeText(change: last.weight - prev.weight) }
                    Spacer()
                }
                Text(last.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + ", "
                     + last.date.formatted(date: .omitted, time: .shortened) + " · " + last.whenLabel)
                    .font(.caption).foregroundStyle(Theme.gray)
                if let p = plan, p.currentIndex() >= 0, let step = p.currentStep, let dry = all.latestForPlan {
                    let diff = dry.weight - step.weight
                    Text((dry.isAfterPractice ? "" : dry == last ? "" : "Last before practice \(dry.weight.lbs): ")
                         + (diff >= 0 ? "\(diff.lbs) lbs over this week's plan weight (\(step.weight.lbs))"
                                      : "\((-diff).lbs) lbs under this week's plan weight (\(step.weight.lbs))"))
                        .font(.subheadline.weight(diff > PortalStore.overPlanFlag ? .semibold : .regular))
                        .foregroundStyle(diff > PortalStore.overPlanFlag ? Theme.red : Theme.gray)
                }
                Text("\(all.count) weigh-in\(all.count == 1 ? "" : "s") logged" + (all.contains(where: \.isCoachEntry) ? " · some by a coach" : " · self-reported")).font(.caption).foregroundStyle(Theme.gray)
            } else {
                Text("No weigh-ins logged yet.").foregroundStyle(Theme.gray)
            }
        }
    }
}

/// Coaches: pick a wrestler's weight class, or go back to the one from their descent plan.
struct WeightClassPicker: View {
    @EnvironmentObject var store: PortalStore
    @Environment(\.dismiss) private var dismiss
    var name: String
    var email: String
    @State private var working = false
    @State private var error: String?

    var body: some View {
        let current = store.weightClass(for: name)
        let fromPlan = store.plan(for: name)?.currentClass
        NavigationStack {
            List {
                Section {
                    Button { Task { await set("") } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use the descent plan").foregroundStyle(Theme.ink)
                                Text(fromPlan.map { "This week: \($0)" } ?? "No descent plan yet").font(.caption).foregroundStyle(Theme.gray)
                            }
                            Spacer()
                            if current?.source != .coach { Image(systemName: "checkmark").foregroundStyle(Theme.red) }
                        }
                    }
                } footer: { Text("Updates on its own each week from the Descent Plans tab.") }
                Section("Set by coach") {
                    ForEach(weightClasses, id: \.self) { c in
                        Button { Task { await set(c) } } label: {
                            HStack {
                                Text(c).font(Theme.display(22)).foregroundStyle(Theme.ink)
                                if c == fromPlan { Text("plan").font(.caption).foregroundStyle(Theme.gray) }
                                Spacer()
                                if current?.source == .coach && current?.cls == c { Image(systemName: "checkmark").foregroundStyle(Theme.red) }
                            }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(Theme.red) } }
            }
            .disabled(working)
            .overlay { if working { ProgressView() } }
            .navigationTitle("\(name.split(separator: " ").first.map(String.init) ?? name)'s Weight Class")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func set(_ c: String) async {
        working = true; error = nil
        defer { working = false }
        do { try await store.setWeightClass(email: email, weightClass: c); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

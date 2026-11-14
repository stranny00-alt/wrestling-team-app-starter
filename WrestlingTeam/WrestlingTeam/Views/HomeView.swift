import SwiftUI

/// Matches the portal's Ironman pane: hero, six tiles, requirement meters, points breakdown, team snapshot.
struct HomeView: View {
    @EnvironmentObject var store: PortalStore
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        NavigationStack {
            ScrollView {
                if let p = store.portal, let m = p.me {
                    VStack(spacing: 14) {
                        HStack(spacing: 8) {
                            Text("Signed in as \(p.email)").font(.caption).foregroundStyle(Theme.gray)
                            Spacer()
                        }
                        Hero(eyebrow: AppConfig.teamName, title: m.name, subtitle: AnyView(HStack(spacing: 8) {
                            StatusBadge(status: m.status)
                            if let wc = store.myWeightClass {
                                Text("\(wc.cls) LBS").font(.system(size: 12, weight: .bold)).tracking(0.5).lineLimit(1).fixedSize()
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .foregroundStyle(Theme.heroInk).background(Theme.gold, in: Capsule())
                            }
                        })) {
                            BigNumber(value: m.total, label: "Ironman Points")
                        }
                        AdaptiveGrid(compact: 3, regular: 6) {
                            Tile(value: m.present, label: "Practices Present")
                            Tile(value: m.absent, label: "Practices Absent")
                            Tile(value: m.pct, label: "Practice Attendance")
                            Tile(value: m.openmat, label: "Open Mats")
                            Tile(value: m.kids, label: "Kids Club Help")
                            Tile(value: m.youth, label: "Youth Tournament")
                        }
                        if let sessions = p.team?[powerSessionsKey] { PowerSpeedCard(count: m.power, sessions: sessions) }
                        requirements(m, p.settings ?? LooseDict())
                        points(m, p.settings ?? LooseDict(), updated: p.updated ?? "")
                        if let team = p.team, !team.values.isEmpty { teamSnapshot(team) }
                    }
                    .padding()
                    .readableWidth()
                }
            }
            .screenBackground()
            .refreshable { await store.load() }
            .navigationTitle(AppConfig.teamName)
            .teamLogo()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Sign Out", role: .destructive) { auth.signOut() }
                    } label: { Image(systemName: "person.crop.circle") }
                }
            }
        }
    }

    private func requirements(_ m: IronmanStats, _ s: LooseDict) -> some View {
        let minPct = number(s["Minimum Practice Attendance %"] ?? "") ?? 95
        let maxAbs = number(s["Maximum Practice Absences"] ?? "")
        let pct = number(m.pct)
        let abs = number(m.absent) ?? 0
        return Card(title: "Ironman Requirements") {
            Meter(label: "Practice attendance", valueText: pct == nil ? "Season not started" : m.pct,
                  note: "/ \(minPct.lbs)% needed", fraction: (pct ?? 0) / 100, marker: minPct / 100,
                  warn: pct != nil && pct! < minPct)
            if let maxAbs {
                Meter(label: "Practice absences", valueText: abs.lbs, note: "/ \(maxAbs.lbs) max",
                      fraction: abs / max(maxAbs, 1), warn: abs > maxAbs)
            }
        }
    }

    private func points(_ m: IronmanStats, _ s: LooseDict, updated: String) -> some View {
        let pp = number(s["Practice points - Present"] ?? "") ?? 0
        let op = number(s["Open Mat points - Present"] ?? "") ?? 0
        let kp = number(s["Kids Club Help points - Present"] ?? "") ?? 0
        let rows: [(String, String, String)] = [
            ("Practices present", "\(m.present.isEmpty ? "0" : m.present) × \(pp.lbs)", ((number(m.present) ?? 0) * pp).lbs),
            ("Open mats", "\(m.openmat.isEmpty ? "0" : m.openmat) × \(op.lbs)", ((number(m.openmat) ?? 0) * op).lbs),
            ("Kids Club help", "\(m.kids.isEmpty ? "0" : m.kids) × \(kp.lbs)", ((number(m.kids) ?? 0) * kp).lbs),
            ("Penalty", "", m.penalty.isEmpty ? "0" : m.penalty),
        ]
        return Card(title: "How Your Points Add Up") {
            VStack(spacing: 8) {
                ForEach(rows, id: \.0) { r in
                    HStack { Text(r.0); Spacer(); Text(r.1).foregroundStyle(Theme.gray); Text(r.2).bold().frame(width: 44, alignment: .trailing) }
                        .font(.subheadline)
                    Divider()
                }
                HStack { Text("Total").bold(); Spacer(); Text(m.total.isEmpty ? "0" : m.total).bold().foregroundStyle(Theme.red) }
            }
            Text("Missing the Kids Club youth tournament is \(s["Kids Club Tournament - Absent penalty"] ?? "") points. Stats update automatically when coaches take attendance. Last checked \(updated).")
                .font(.caption).foregroundStyle(Theme.gray)
        }
    }

    private func teamSnapshot(_ t: LooseDict) -> some View {
        let keys = ["Wrestlers Tracked", "Practice Sessions", "Open Mat Sessions", powerSessionsKey, "Current Ironmen", "Team Practice %"].filter { t[$0] != nil }
        return Card(title: "Team Snapshot") {
            ForEach(keys, id: \.self) { k in
                HStack { Text(k).font(.subheadline); Spacer(); Text(t[k] ?? "").font(.subheadline.bold()) }
            }
        }
    }
}

import SwiftUI

/// The wrestler's own descent plan (only sent after they sign the handbook), like descentView() in the portal.
struct DescentView: View {
    @EnvironmentObject var store: PortalStore
    @Binding var tab: AppTab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let p = store.portal?.descent {
                        if p.steps.isEmpty {
                            Card(title: "No descent plan yet") {
                                Text("You don't have a weight descent plan on file. If you think you should, talk to \(AppConfig.handbookCoach).")
                            }
                        } else {
                            DescentPlanContent(plan: p, notes: store.portal?.descentNotes ?? LooseDict(), latest: store.weighIns.latestForPlan)
                        }
                    } else {
                        locked
                    }
                }
                .padding()
                .readableWidth()
            }
            .screenBackground()
            .refreshable { await store.load() }
            .navigationTitle("Descent Plan")
            .teamLogo()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var locked: some View {
        Card(title: "Your Weight Descent Plan") {
            Label("Locked", systemImage: "lock.fill").font(Theme.display(26)).foregroundStyle(Theme.red)
            Text("Your descent plan unlocks as soon as you sign off on the Team Handbook.")
            Button("Go to Handbook") { tab = .handbook }.buttonStyle(.borderedProminent).tint(Theme.red)
        }
    }
}

/// One wrestler's descent plan (hero, tiles, last weigh-in vs. this week, week by week). Used by wrestlers and coaches.
struct DescentPlanContent: View {
    var plan: DescentPlan
    var notes: LooseDict
    var latest: WeighIn?
    var forCoach = false

    var body: some View {
        VStack(spacing: 14) {
        let p = plan
        let i = p.currentIndex()
        let cur = p.currentStep!
        let next = p.nextStepDown
        let lock = DateParsing.mdy(notes["Minimum weight locked"] ?? "")
        let daysToLock = lock.map { Int(ceil($0.timeIntervalSince(Calendar.current.startOfDay(for: Date())) / 86_400)) }
        let curDay = cur.day.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? cur.date

        Hero(eyebrow: "Weight Descent Plan · " + (i >= 0 ? "Week of \(curDay)" : "Starts \(curDay)"),
             title: "\(cur.weight.lbs) lbs",
             subtitle: AnyView(VStack(alignment: .leading, spacing: 8) {
                 Text("Lowest eligible weight right now").font(.footnote).foregroundStyle(Theme.lightText)
                 HStack { ForEach(Array(cur.classes.enumerated()), id: \.offset) { j, c in Chip(text: c, highlighted: j == 0) } }
                 Text("Weight classes you can wrestle this week").font(.caption2).foregroundStyle(Theme.lightText)
             })) {
            BigNumber(value: p.minClass, label: "Lowest Class")
        }

        AdaptiveGrid(compact: 2, regular: 4) {
            Tile(value: number(p.minWeight)?.lbs ?? p.minWeight, label: "Minimum Weight", detail: "lowest you can certify")
            Tile(value: number(p.perWeek)?.lbs ?? p.perWeek, label: "Max Drop / Week", detail: "lbs (NFHS 1.5% rule)")
            Tile(value: next?.weight.lbs ?? "—", label: "Next Step Down",
                 detail: next?.day.map { "Week of " + $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "You're at your lowest class")
            Tile(value: daysToLock.map { $0 > 0 ? String($0) : "Locked" } ?? "—",
                 label: (daysToLock ?? 0) > 0 ? "Days Until Weight Locks" : "Minimum Weight",
                 detail: lock?.formatted(date: .abbreviated, time: .omitted))
        }

        if let last = latest {
            Card(title: (forCoach ? "Last" : "Your Last") + " Weigh-In vs. This Week") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(last.weight.lbs) lbs").font(Theme.display(28))
                        Text("\(last.whenLabel) · \(last.date.formatted(.dateTime.month(.abbreviated).day()))").font(.caption).foregroundStyle(Theme.gray)
                    }
                    Spacer()
                    let diff = last.weight - cur.weight
                    VStack(alignment: .trailing) {
                        Text(diff >= 0 ? "\(diff.lbs) lbs above" : "\((-diff).lbs) lbs below").font(.headline)
                            .foregroundStyle(diff >= 0 ? Theme.ink : Theme.red)
                        Text("this week's lowest eligible (\(cur.weight.lbs))").font(.caption).foregroundStyle(Theme.gray)
                    }
                }
                if last.weight < cur.weight {
                    Text(forCoach ? "Under the lowest weight the plan allows this week." : "You're under the lowest weight your plan allows this week. Talk to \(AppConfig.handbookCoach).")
                        .font(.caption).foregroundStyle(Theme.red)
                }
            }
        }

        Card(title: "Week by Week") {
            ForEach(Array(p.steps.enumerated()), id: \.offset) { k, s in
                HStack {
                    Text(s.day.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? s.date).frame(width: 64, alignment: .leading)
                    Text(s.weight.lbs).bold().frame(width: 56, alignment: .trailing)
                    Text(s.classes.joined(separator: ", ")).foregroundStyle(Theme.gray).frame(maxWidth: .infinity, alignment: .trailing)
                    Group {
                        if k == i { Text("This week").foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.red, in: Capsule()) }
                        else if k < i { Text("Done").foregroundStyle(Theme.gray) }
                        else { Text("") }
                    }
                    .font(.caption2.bold()).frame(width: 66, alignment: .trailing)
                }
                .font(.subheadline)
                .opacity(k < i ? 0.55 : 1)
                if k < p.steps.count - 1 { Divider() }
            }
            Text("This plan shows the fastest your weight is allowed to come down under NFHS rules (no more than 1.5% of body weight per week). It is a limit, not a goal. Eat, hydrate and sleep well, and talk to \(AppConfig.handbookCoach) before changing your weight class.")
                .font(.caption).foregroundStyle(Theme.gray).padding(.top, 4)
        }
        }
    }
}

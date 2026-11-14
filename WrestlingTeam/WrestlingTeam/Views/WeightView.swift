import SwiftUI

/// Self-reported weigh-ins: log a weight, see it against this week's descent plan, and the history.
struct WeightView: View {
    @EnvironmentObject var store: PortalStore
    @Binding var tab: AppTab
    @State private var showLog = false

    private var plan: DescentPlan? { store.portal?.descent }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    thisWeek
                    if let practice = lastPractice { practice }
                    Button { showLog = true } label: {
                        Label("Log My Weight", systemImage: "plus.circle.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.red)
                    if store.weighIns.count >= 2 { WeighInChart(entries: store.weighIns, plan: plan, title: "Your Weigh-Ins") }
                    WeighInHistory(entries: store.weighIns)
                    NavigationLink { WeightClassPlanView() } label: {
                        HStack {
                            Image(systemName: "list.bullet.clipboard")
                            Text("Weight class plan (before & after Christmas)")
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.gray)
                        }
                        .font(.subheadline).padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                    }
                    .foregroundStyle(Theme.ink)
                }
                .padding()
                .readableWidth()
            }
            .screenBackground()
            .refreshable { await store.load() }
            .navigationTitle("My Weight")
            .teamLogo()
            .sheet(isPresented: $showLog) { LogWeightView().environmentObject(store) }
        }
    }

    /// Most recent practice with both a before and an after weigh-in.
    private var lastPractice: AnyView? {
        guard let after = store.weighIns.first(where: { store.weighIns.practiceLoss(for: $0) != nil }),
              let before = store.weighIns.beforePractice(matching: after) else { return nil }
        let loss = before.weight - after.weight
        return AnyView(Card(title: Calendar.current.isDateInToday(after.date) ? "Today's Practice" : "Last Practice · \(after.date.shortAgo)") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(before.weight.lbs) → \(after.weight.lbs)").font(Theme.display(24))
                    Text("Before → after practice").font(.caption).foregroundStyle(Theme.gray)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text((loss >= 0 ? "−" : "+") + abs(loss).lbs + " lbs").font(Theme.display(24)).foregroundStyle(Theme.red)
                    Text(String(format: "%.1f%% of body weight", abs(loss) / before.weight * 100)).font(.caption).foregroundStyle(Theme.gray)
                }
            }
        })
    }

    private var thisWeek: some View {
        // Lead with the weight that counts for the plan (before practice); the Last Practice card shows the after weight.
        let dry = store.weighIns.latestForPlan
        let last = dry ?? store.latest
        let step = plan?.currentIndex() ?? -1 >= 0 ? plan?.currentStep : nil
        return Hero(eyebrow: "Last weigh-in · " + (last?.whenLabel.lowercased() ?? "self-reported"),
                    title: last.map { "\($0.weight.lbs) lbs" } ?? "No weigh-ins yet",
                    subtitle: AnyView(Text(last.map { $0.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()) } ?? "Tap Log My Weight to add your first one.")
                        .font(.footnote).foregroundStyle(Theme.lightText))) {
            if let step {
                VStack(spacing: 2) {
                    Text(step.weight.lbs).font(Theme.display(30)).foregroundStyle(.white)
                    Text("THIS WEEK'S\nLOWEST ELIGIBLE").font(.system(size: 8, weight: .bold)).multilineTextAlignment(.center).foregroundStyle(Theme.lightText)
                    if let dry {
                        let diff = dry.weight - step.weight
                        Text(diff >= 0 ? "+\(diff.lbs) above" : "\((-diff).lbs) below")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(diff >= 0 ? Theme.gold : .white)
                            .padding(.top, 2)
                    }
                }
                .padding(10).background(Theme.red, in: RoundedRectangle(cornerRadius: 12))
            } else if store.portal?.descentLocked == true {
                Button { tab = .handbook } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                        Text("Sign the\nhandbook to\nsee your plan").font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white).padding(10).background(Theme.red, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

}

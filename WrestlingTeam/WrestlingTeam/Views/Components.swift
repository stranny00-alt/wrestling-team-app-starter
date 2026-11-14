import SwiftUI

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title.uppercased()).font(Theme.display(17, weight: .semibold)).foregroundStyle(Theme.ink) }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }
}

struct Tile: View {
    var value: String
    var label: String
    var detail: String? = nil
    var body: some View {
        VStack(spacing: 4) {
            Text(value.isEmpty ? "—" : value).font(Theme.display(26)).foregroundStyle(Theme.ink).minimumScaleFactor(0.6).lineLimit(1)
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.gray).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.75)
            if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(Theme.gray.opacity(0.8)).multilineTextAlignment(.center) }
        }
        .padding(.vertical, 12).padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }
}

struct StatusBadge: View {
    var status: String
    var compact = false
    var body: some View {
        let tone = StatusTone(status)
        Text(status.isEmpty ? "—" : status.uppercased())
            .font(.system(size: compact ? 10 : 12, weight: .bold)).tracking(compact ? 0.2 : 0.5)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, compact ? 8 : 10).padding(.vertical, compact ? 3 : 4)
            .foregroundStyle(tone == .good ? Theme.ok : tone == .bad ? Theme.red : Theme.heroInk)
            .background(tone == .good ? Theme.okBG : tone == .bad ? Theme.noBG : Theme.gold, in: Capsule())
    }
}

/// Dark hero header like the portal's .hero block.
struct Hero<Trailing: View>: View {
    var eyebrow: String
    var title: String
    var subtitle: AnyView? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow.uppercased()).font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(Theme.gold)
                Text(title).font(Theme.display(30)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.7)
                subtitle
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(18)
        // Big faded team logo behind the header, like a jersey graphic.
        .background(alignment: .trailing) {
            Image("TeamLogo").resizable().scaledToFit()
                .frame(height: 190)
                .opacity(0.09)
                .rotationEffect(.degrees(-8))
                .offset(x: 40, y: 18)
                .accessibilityHidden(true)
        }
        .background(LinearGradient(colors: [Theme.heroInk, Theme.ink2], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08)))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.red).frame(height: 4).clipShape(RoundedRectangle(cornerRadius: 2)).padding(.horizontal, 18) }
    }
}

struct BigNumber: View {
    var value: String
    var label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value.isEmpty ? "0" : value).font(Theme.display(40)).foregroundStyle(.white)
            Text(label.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(Theme.lightText)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.red, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Meter: View {
    var label: String
    var valueText: String
    var note: String
    var fraction: Double
    var marker: Double? = nil
    var warn: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(valueText).font(.subheadline.bold()) + Text("  \(note)").font(.caption).foregroundColor(Theme.gray)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.soft)
                    Capsule().fill(warn ? Theme.red : Theme.ok).frame(width: g.size.width * min(max(fraction, 0), 1))
                    if let marker { Rectangle().fill(Theme.ink).frame(width: 2, height: 14).offset(x: g.size.width * min(marker, 1) - 1) }
                }
            }
            .frame(height: 10)
        }
    }
}

struct Chip: View {
    var text: String
    var highlighted = false
    var body: some View {
        Text(text).font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(highlighted ? Theme.heroInk : .white)
            .background(highlighted ? Theme.gold : Color.white.opacity(0.14), in: Capsule())
    }
}

struct ErrorCard: View {
    var error: APIError
    var retry: () async -> Void
    var body: some View {
        Card(title: error.code == "notfound" ? "Not linked yet" : "Couldn't load") {
            Text(error.message).foregroundStyle(Theme.gray)
            Button("Try Again") { Task { await retry() } }.buttonStyle(.borderedProminent)
        }
    }
}

/// The team logo for the top bar of each main screen.
struct TeamLogoMark: View {
    var body: some View {
        Image("TeamLogo").resizable().scaledToFit()
            .frame(width: 30, height: 30)
            .accessibilityLabel(AppConfig.teamName)
    }
}

extension View {
    /// Puts the team logo at the left of the navigation bar.
    func teamLogo() -> some View {
        toolbar { ToolbarItem(placement: .topBarLeading) { TeamLogoMark() } }
    }

    func screenBackground() -> some View { background(Theme.soft.ignoresSafeArea()) }

    /// Keeps a screen's cards a comfortable reading width on iPad; no effect on iPhone.
    func readableWidth(_ max: CGFloat = 760) -> some View {
        frame(maxWidth: max).frame(maxWidth: .infinity)
    }
}

/// Tile grid columns: `compact` across on iPhone; on iPad `regular` across when the space is wide enough
/// (an iPad split view's detail column often isn't), otherwise `compact`.
struct AdaptiveGrid<Content: View>: View {
    var compact: Int
    var regular: Int
    var minTile: CGFloat = 112
    @ViewBuilder var content: Content
    @Environment(\.horizontalSizeClass) private var hsc
    @State private var width: CGFloat = 0
    var body: some View {
        let needed = CGFloat(regular) * minTile + CGFloat(regular - 1) * 10
        let n = hsc == .regular && width >= needed ? regular : compact
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: n), spacing: 10) { content }
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { width = g.size.width }
                    .onChange(of: g.size.width) { _, w in width = w }
            })
    }
}

/// Power/Speed attendance: tracked for coaches, not part of Ironman points.
/// Shown once the sheet has a Power/Speed tab (the script then sends the session count).
struct PowerSpeedCard: View {
    var count: String
    var sessions: String
    var forCoach = false
    var body: some View {
        let n = number(count) ?? 0, total = number(sessions) ?? 0
        Card {
            Meter(label: "Power/Speed", valueText: n.lbs, note: "of \(total.lbs) sessions",
                  fraction: total > 0 ? n / total : 0, warn: false)
            Text(forCoach ? "Tracked only. It doesn't change Ironman points." : "Tracked for coaches. It doesn't change your Ironman points.")
                .font(.caption).foregroundStyle(Theme.gray)
        }
    }
}

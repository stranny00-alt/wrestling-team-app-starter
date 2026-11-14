import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    var body: some View {
        switch auth.state {
        case .checking:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).screenBackground()
        case .signedOut:
            SignInView()
        case .signedIn(let email, _):
            MainView(api: auth.api).id(email)
        }
    }
}

enum AppTab: Hashable { case home, weight, plan, handbook, team }

struct MainView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var store: PortalStore
    @State private var tab: AppTab = {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "StartTab") {   // -StartTab weight|plan|handbook (screenshots)
        case "weight": return .weight
        case "plan": return .plan
        case "handbook": return .handbook
        default: break
        }
        #endif
        return .home
    }()

    init(api: PortalAPI) { _store = StateObject(wrappedValue: PortalStore(api: api)) }

    var body: some View {
        Group {
            if let p = store.portal {
                if p.isCoach { coachTabs(p) } else { wrestlerTabs(p) }
            } else if let e = store.error {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if case .signedIn(let email, _) = auth.state {
                                Text("Signed in as \(email)").font(.caption).foregroundStyle(Theme.gray)
                            }
                            ErrorCard(error: e, retry: store.load)
                        }
                        .padding()
                        .readableWidth()
                    }
                        .screenBackground()
                        .toolbar { Button("Sign Out") { auth.signOut() } }
                }
            } else {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity).screenBackground()
            }
        }
        .environmentObject(store)
        .task { await store.load() }
    }

    @ViewBuilder private func wrestlerTabs(_ p: PortalData) -> some View {
        TabView(selection: $tab) {
            if p.me != nil {
                HomeView().tabItem { Label("Home", systemImage: "house.fill") }.tag(AppTab.home)
            }
            WeightView(tab: $tab).tabItem { Label("Weight", systemImage: "scalemass.fill") }.tag(AppTab.weight)
            if p.hasDescentTab {
                DescentView(tab: $tab).tabItem { Label("Descent Plan", systemImage: "chart.line.downtrend.xyaxis") }.tag(AppTab.plan)
            }
            HandbookView().tabItem { Label("Handbook", systemImage: "book.closed.fill") }.tag(AppTab.handbook)
        }
        .onAppear { if p.me == nil && tab == .home { tab = .weight } }
    }

    @ViewBuilder private func coachTabs(_ p: PortalData) -> some View {
        CoachTabs()
    }
}

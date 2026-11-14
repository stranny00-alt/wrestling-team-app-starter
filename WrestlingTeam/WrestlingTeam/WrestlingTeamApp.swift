import SwiftUI
import GoogleSignIn

@main
struct WrestlingTeamApp: App {
    @StateObject private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .tint(Theme.red)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .task { await auth.restore() }
        }
    }
}

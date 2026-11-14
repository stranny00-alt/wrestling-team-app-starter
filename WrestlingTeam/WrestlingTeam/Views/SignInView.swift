import SwiftUI

struct SignInView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var working = false

    /// Screenshots only (-ScreenshotSignIn YES): show the real sign-in wording even in sample mode.
    private var showSampleWording: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ScreenshotSignIn") { return false }
        #endif
        return auth.sampleMode
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(.white).frame(width: 150, height: 150)
                    Image("TeamLogo").resizable().scaledToFit().frame(width: 118, height: 118)
                }
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                .accessibilityLabel("\(AppConfig.teamName) logo")
                Text(AppConfig.teamName.uppercased()).font(Theme.display(34)).foregroundStyle(.white).tracking(1)
                Text("TEAM APP").font(.system(size: 13, weight: .bold)).tracking(3).foregroundStyle(Theme.gold)
                Text("Points, weigh-ins, your descent plan, and the team handbook in one place.")
                    .font(.subheadline).foregroundStyle(Theme.lightText).multilineTextAlignment(.center).padding(.top, 4)
            }
            .padding(.horizontal, 24)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    working = true
                    Task { await auth.signIn(); working = false }
                } label: {
                    HStack(spacing: 10) {
                        if working { ProgressView().tint(Theme.heroInk) } else { Image(systemName: "person.crop.circle.fill") }
                        Text(showSampleWording ? "Continue with Sample Data" : "Sign in with School Google")
                    }
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .foregroundStyle(Theme.heroInk).background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(working)
                if let msg = auth.errorMessage {
                    Text(msg).font(.footnote).foregroundStyle(Theme.gold).multilineTextAlignment(.center)
                }
                Text(showSampleWording
                     ? "Sample mode: made-up data, nothing is saved to the team sheet."
                     : "Use your @\(AppConfig.schoolDomain) account.")
                    .font(.footnote).foregroundStyle(Theme.lightText).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24).padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Theme.redDark, Theme.heroInk], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        )
    }
}

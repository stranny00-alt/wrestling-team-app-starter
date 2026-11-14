import SwiftUI
import GoogleSignIn

/// School Google sign-in (openid email profile only). In sample mode it just pretends.
@MainActor
final class AuthManager: ObservableObject {
    enum State { case checking, signedOut, signedIn(email: String, name: String) }

    @Published var state: State = .checking
    @Published var errorMessage: String?
    let sampleMode = AppConfig.useSampleData
    private(set) var api: PortalAPI = SampleAPI()

    init() {
        if !sampleMode, let url = AppConfig.apiURL {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(
                clientID: AppConfig.clientID, serverClientID: nil, hostedDomain: AppConfig.schoolDomain, openIDRealm: nil)
            api = LiveAPI(url: url, idToken: { try await AuthManager.freshIDToken() })
        }
    }

    func restore() async {
        if sampleMode {
            state = .signedOut
            #if DEBUG
            // Screenshots: launch with -AutoSampleSignIn YES to skip the sign-in screen.
            if UserDefaults.standard.bool(forKey: "AutoSampleSignIn") { await signIn() }
            #endif
            return
        }
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            accept(user)
        } catch {
            state = .signedOut
        }
    }

    func signIn() async {
        errorMessage = nil
        if sampleMode {
            api = SampleAPI()
            state = SampleAPI.coachMode ? .signedIn(email: SampleAPI.coachEmail, name: "Sample Coach")
                                        : .signedIn(email: SampleAPI.email, name: "Jordan Miller")
            return
        }
        guard let presenter = Self.topViewController() else { return }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: nil)
            accept(result.user)
        } catch let e as NSError where e.domain == kGIDSignInErrorDomain && e.code == GIDSignInError.canceled.rawValue {
            // they closed the Google sheet; nothing to say
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        if !sampleMode { GIDSignIn.sharedInstance.signOut() }
        state = .signedOut
    }

    private func accept(_ user: GIDGoogleUser) {
        let email = (user.profile?.email ?? "").lowercased()
        guard email.hasSuffix("@" + AppConfig.schoolDomain) else {
            GIDSignIn.sharedInstance.signOut()
            errorMessage = "Please sign in with your \(AppConfig.schoolDomain) school account."
            state = .signedOut
            return
        }
        state = .signedIn(email: email, name: user.profile?.name ?? email)
    }

    /// ID tokens last about an hour; refresh before each call if needed.
    nonisolated static func freshIDToken() async throws -> String {
        guard let user = await MainActor.run(body: { GIDSignIn.sharedInstance.currentUser }) else {
            throw APIError(code: "auth", message: "Please sign in again.")
        }
        let fresh = try await user.refreshTokensIfNeeded()
        guard let token = fresh.idToken?.tokenString else { throw APIError(code: "auth", message: "Please sign in again.") }
        return token
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let p = top?.presentedViewController { top = p }
        return top
    }
}

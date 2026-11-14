import Foundation

/// Values come from Config.xcconfig via Info.plist. Until the real iOS client ID is pasted in,
/// the app runs on built-in sample data and never contacts Google or the sheet.
enum AppConfig {
    // ── YOUR TEAM ─────────────────────────────────────────────────────────────
    /// Your school's Google Workspace domain. Only accounts @this domain can sign in.
    static let schoolDomain = "yourschool.org"
    /// Shown on the sign-in screen, Home and the coach Team Overview.
    static let teamName = "Your Team Wrestling"
    /// Who wrestlers should talk to, used in a few messages.
    static let handbookCoach = "your coach"
    // Team colors are in Theme.swift; the logo is the TeamLogo image set in Assets.xcassets.
    // ──────────────────────────────────────────────────────────────────────────

    static var clientID: String { info("GIDClientID") }
    static var deploymentID: String { info("APIDeploymentID") }

    static var apiURL: URL? {
        let id = deploymentID
        guard !id.isEmpty, !id.contains("PASTE") else { return nil }
        return URL(string: "https://script.google.com/macros/s/\(id)/exec")
    }

    /// Sample mode: no real client ID / API yet, or launched with `-SampleData YES`.
    static var useSampleData: Bool {
        if UserDefaults.standard.bool(forKey: "SampleData") { return true }
        return clientID.isEmpty || clientID.contains("PASTE") || apiURL == nil
    }

    private static func info(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}

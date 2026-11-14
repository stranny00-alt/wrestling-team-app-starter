import Foundation

/// Everything the app can ask the Apps Script for. One live version (the sheet) and one sample version.
protocol PortalAPI {
    func home() async throws -> PortalData
    func weighIns() async throws -> [WeighIn]
    func logWeighIn(_ weight: Double, when: WeighInWhen) async throws -> WeighIn
    func handbook() async throws -> HandbookInfo
    func signHandbook(typed: String) async throws -> SignHandbookResult
    func weightPlan() async throws -> WeightPlanInfo
    func saveWeightPlan(before: String, after: String, current: String, notes: String) async throws
    // Coaches only (the script refuses these for wrestlers)
    func teamWeighIns() async throws -> [WrestlerWeighIns]
    func handbookList() async throws -> HandbookList
    func attendance(kind: AttendanceKind, date: String) async throws -> AttendanceSession
    func saveAttendance(kind: AttendanceKind, date: String, marks: [String: String], notes: String) async throws -> AttendanceSaveResult
    // Coaches: punch in a wrestler's weight, fix one of their entries, or delete one.
    func coachLogWeighIn(email: String, weight: Double, when: WeighInWhen) async throws -> WeighIn
    func editWeighIn(email: String, at: String, weight: Double, when: WeighInWhen?) async throws -> WeighIn
    func deleteWeighIn(email: String, at: String) async throws
    /// Coaches: set a wrestler's weight class; "" goes back to the one from their descent plan.
    func setWeightClass(email: String, weightClass: String) async throws -> SetWeightClassResult
}

struct APIError: LocalizedError {
    var code: String
    var message: String
    var errorDescription: String? { message }
    var needsSignIn: Bool { code == "auth" }
}

/// Talks to doPost() in the Ironman Tracker's Apps Script. Every call carries a fresh Google ID token.
struct LiveAPI: PortalAPI {
    let url: URL
    let idToken: () async throws -> String

    private struct Envelope<T: Decodable>: Decodable {
        var ok: Bool
        var data: T?
        var error: String?
        var message: String?
    }

    private func call<T: Decodable>(_ action: String, _ args: [String: Any] = [:]) async throws -> T {
        var body = args
        body["action"] = action
        body["idToken"] = try await idToken()
        var req = URLRequest(url: url, timeoutInterval: 45)
        req.httpMethod = "POST"
        // text/plain keeps Apps Script happy (it reads e.postData.contents either way).
        req.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Apps Script answers with a redirect to script.googleusercontent.com; URLSession follows it.
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError(code: "http", message: "The team server didn't answer. Check your connection and try again.")
        }
        let env: Envelope<T>
        do { env = try JSONDecoder().decode(Envelope<T>.self, from: data) }
        catch { throw APIError(code: "decode", message: "Got an unexpected answer from the team server.") }
        guard env.ok, let value = env.data else {
            throw APIError(code: env.error ?? "failed", message: env.message ?? "Something went wrong.")
        }
        return value
    }

    func home() async throws -> PortalData { try await call("home") }
    func weighIns() async throws -> [WeighIn] { (try await call("weighIns") as WeighInList).weighIns }
    func logWeighIn(_ weight: Double, when: WeighInWhen) async throws -> WeighIn {
        (try await call("logWeighIn", ["weight": weight, "when": when.rawValue]) as LogWeighInResult).weighIn
    }
    func handbook() async throws -> HandbookInfo { try await call("handbook") }
    func signHandbook(typed: String) async throws -> SignHandbookResult { try await call("signHandbook", ["typed": typed]) }
    func weightPlan() async throws -> WeightPlanInfo { try await call("weightPlan") }
    func saveWeightPlan(before: String, after: String, current: String, notes: String) async throws {
        let _: OKResult = try await call("saveWeightPlan", ["before": before, "after": after, "current": current, "notes": notes])
    }
    func teamWeighIns() async throws -> [WrestlerWeighIns] {
        (try await call("teamWeighIns", ["limit": 120]) as TeamWeighIns).wrestlers
    }
    func handbookList() async throws -> HandbookList { try await call("handbookList") }
    func attendance(kind: AttendanceKind, date: String) async throws -> AttendanceSession {
        try await call("attendance", ["kind": kind.rawValue, "date": date])
    }
    func saveAttendance(kind: AttendanceKind, date: String, marks: [String: String], notes: String) async throws -> AttendanceSaveResult {
        try await call("saveAttendance", ["kind": kind.rawValue, "date": date, "marks": marks, "notes": notes])
    }
    func coachLogWeighIn(email: String, weight: Double, when: WeighInWhen) async throws -> WeighIn {
        (try await call("coachLogWeighIn", ["wrestlerEmail": email, "weight": weight, "when": when.rawValue]) as LogWeighInResult).weighIn
    }
    func editWeighIn(email: String, at: String, weight: Double, when: WeighInWhen?) async throws -> WeighIn {
        var args: [String: Any] = ["wrestlerEmail": email, "at": at, "weight": weight]
        if let when { args["when"] = when.rawValue }
        return (try await call("editWeighIn", args) as EditWeighInResult).weighIn
    }
    func deleteWeighIn(email: String, at: String) async throws {
        let _: OKResult = try await call("deleteWeighIn", ["wrestlerEmail": email, "at": at])
    }
    func setWeightClass(email: String, weightClass: String) async throws -> SetWeightClassResult {
        try await call("setWeightClass", ["wrestlerEmail": email, "weightClass": weightClass])
    }
}

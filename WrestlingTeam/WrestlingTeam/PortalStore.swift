import SwiftUI

/// Holds what the signed-in wrestler sees. Loaded from the API (live sheet or sample data).
@MainActor
final class PortalStore: ObservableObject {
    @Published var portal: PortalData?
    @Published var weighIns: [WeighIn] = []
    @Published var loading = false
    @Published var error: APIError?

    let api: PortalAPI
    init(api: PortalAPI) { self.api = api }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let p = try await api.home()
            portal = p
            weighIns = (p.weighIns ?? []).sorted { $0.date > $1.date }
            error = nil
        } catch let e as APIError {
            error = e
        } catch {
            self.error = APIError(code: "network", message: "Couldn't reach the team server. Check your connection and pull to refresh.")
        }
    }

    func logWeight(_ w: Double, when: WeighInWhen) async throws {
        let entry = try await api.logWeighIn(w, when: when)
        weighIns.insert(entry, at: 0)
    }

    var latest: WeighIn? { weighIns.first }

    // MARK: Coach data

    @Published var team: [WrestlerWeighIns] = []
    @Published var teamError: String?
    @Published var handbook: HandbookList?
    @Published var handbookError: String?

    func loadCoachData() async {
        async let t: Void = loadTeam()
        async let h: Void = loadHandbookList()
        _ = await (t, h)
    }

    func loadTeam() async {
        do { team = try await api.teamWeighIns(); teamError = nil }
        catch { teamError = error.localizedDescription }
    }

    func loadHandbookList() async {
        do { handbook = try await api.handbookList(); handbookError = nil }
        catch { handbookError = error.localizedDescription }
    }

    func refreshAll() async {
        await load()
        if portal?.isCoach == true { await loadCoachData() }
    }

    private func same(_ a: String, _ b: String) -> Bool { a.trimmingCharacters(in: .whitespaces).lowercased() == b.trimmingCharacters(in: .whitespaces).lowercased() }
    func stats(for name: String) -> IronmanStats? { portal?.wrestlers?.first { same($0.name, name) } }
    func weighIns(for name: String) -> WrestlerWeighIns? { team.first { same($0.name, name) } }
    func plan(for name: String) -> DescentPlan? { portal?.descents?.first { same($0.name, name) } }

    // MARK: Attendance cache: sessions already loaded ("kind|yyyy-MM-dd"), so switching back is instant.
    var attendanceCache: [String: AttendanceSession] = [:]

    // MARK: Coach weigh-ins (punch in, fix, delete). Keeps the team list in step without a reload.

    func coachLogWeight(name: String, email: String, weight: Double, when: WeighInWhen) async throws -> WeighIn {
        let w = try await api.coachLogWeighIn(email: email, weight: weight, when: when)
        if let i = team.firstIndex(where: { same($0.email, email) }) { team[i].weighIns.insert(w, at: 0) }
        return w
    }

    func editWeighIn(email: String, entry: WeighIn, weight: Double, when: WeighInWhen?) async throws -> WeighIn {
        let w = try await api.editWeighIn(email: email, at: entry.at, weight: weight, when: when)
        if let i = team.firstIndex(where: { same($0.email, email) }),
           let k = team[i].weighIns.firstIndex(where: { $0.at == entry.at }) { team[i].weighIns[k] = w }
        return w
    }

    func deleteWeighIn(email: String, entry: WeighIn) async throws {
        try await api.deleteWeighIn(email: email, at: entry.at)
        if let i = team.firstIndex(where: { same($0.email, email) }) { team[i].weighIns.removeAll { $0.at == entry.at } }
    }

    /// Latest before-practice (or other) weight and how far it is from this week's lowest eligible weight
    /// (negative = below the plan). Nil if there's no plan running this week or no weigh-in.
    func planGap(for name: String) -> (weight: Double, gap: Double)? {
        guard let p = plan(for: name), p.currentIndex() >= 0, let step = p.currentStep,
              let dry = weighIns(for: name)?.weighIns.latestForPlan else { return nil }
        return (dry.weight, dry.weight - step.weight)
    }

    // MARK: Weight class: a coach's override, else this week's lowest eligible class from the descent plan.

    func weightClass(for name: String) -> (cls: String, source: ClassSource)? {
        if let e = email(for: name), let o = portal?.classOverrides?[e.lowercased()], !o.weightClass.isEmpty { return (o.weightClass, .coach) }
        if let c = plan(for: name)?.currentClass { return (c, .plan) }
        return nil
    }
    func classOverride(for name: String) -> ClassOverride? {
        email(for: name).flatMap { portal?.classOverrides?[$0.lowercased()] }
    }
    /// The signed-in wrestler's own class.
    var myWeightClass: (cls: String, source: ClassSource)? {
        if let c = portal?.weightClass, !c.isEmpty { return (c, .coach) }
        if let c = portal?.descent?.currentClass { return (c, .plan) }
        return nil
    }

    /// Coaches: set (or with "" clear) a wrestler's weight class.
    func setWeightClass(email: String, weightClass: String) async throws {
        let r = try await api.setWeightClass(email: email, weightClass: weightClass)
        var map = portal?.classOverrides ?? [:]
        map[email.lowercased()] = r.weightClass.isEmpty ? nil : ClassOverride(weightClass: r.weightClass, by: r.by ?? "", updated: r.updated ?? "")
        portal?.classOverrides = map
    }

    /// Coaches see a flag when a wrestler's latest before-practice weight is more than this over this week's plan weight.
    static let overPlanFlag = 5.0
    func isWellOverPlan(_ name: String) -> Bool { (planGap(for: name)?.gap ?? 0) > Self.overPlanFlag }

    /// School email for a wrestler (from the weigh-ins roster or their descent plan).
    func email(for name: String) -> String? {
        if let e = weighIns(for: name)?.email, !e.isEmpty { return e }
        if let e = plan(for: name)?.email, !e.isEmpty { return e }
        return nil
    }

    /// List rows pick wrestlers by name, but accept a school email too (an iPad list selection can hand over a row's id).
    func resolveName(_ key: String) -> String {
        guard key.contains("@") else { return key }
        if let w = team.first(where: { same($0.email, key) }) { return w.name }
        if let p = portal?.descents?.first(where: { same($0.email, key) }) { return p.name }
        return key
    }
}

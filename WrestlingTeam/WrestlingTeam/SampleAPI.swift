import Foundation

/// Made-up data so the app can be built and tried before the Google pieces exist. Nothing here touches the sheet.
actor SampleAPI: PortalAPI {
    static let email = "miller2030@\(AppConfig.schoolDomain)"
    private let name = "Jordan Miller"
    private var log: [WeighIn]
    private var signed = ""
    private var plan: WeightClassPlan? = nil
    private let descent: DescentPlan
    /// Sample attendance, keyed "kind|yyyy-MM-dd".
    private var attendanceLog: [String: (marks: [String: String], notes: String)] = [:]

    init() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Plan weeks start on Mondays, three weeks back, like the "Week N · M/D/YYYY" columns.
        let weekday = cal.component(.weekday, from: today)
        let monday = cal.date(byAdding: .day, value: -((weekday + 5) % 7), to: today)!
        let start = cal.date(byAdding: .day, value: -21, to: monday)!
        let f = DateFormatter(); f.dateFormat = "M/d/yyyy"; f.locale = Locale(identifier: "en_US_POSIX")
        let classes = [106, 113, 120, 126, 132, 138, 144, 150, 157, 165, 175, 190, 215, 285]
        var steps: [DescentStep] = []
        var w = 151.0
        for k in 0..<9 {
            w = max(137.5, w * 0.985)
            let d = cal.date(byAdding: .day, value: 7 * k, to: start)!
            let ok = classes.filter { Double($0) >= w }.prefix(2).map(String.init)
            steps.append(DescentStep(label: "Week \(k + 1)", date: f.string(from: d), weight: (w * 100).rounded() / 100, classes: ok))
        }
        descent = DescentPlan(email: Self.email, name: name, perWeek: "2.2", minClass: "138", minWeight: "137.5", steps: steps)

        var entries: [WeighIn] = []
        let base: [Double] = [151.2, 150.6, 150.8, 149.9, 149.4, 149.8, 148.9, 148.6, 148.2, 148.7, 147.9, 147.6]
        let sweat: [Double] = [3.2, 2.8, 3.6, 2.6, 3.0, 3.4, 2.4, 3.1, 2.9, 3.3, 2.7, 3.0]
        for (i, wt) in base.enumerated() {
            // Practice days: weigh before (3:20) and after (5:45).
            let d = cal.date(byAdding: .day, value: -(base.count - i) * 2, to: Date())!
            entries.append(WeighIn(at: DateParsing.isoString(cal.date(bySettingHour: 15, minute: 20, second: 0, of: d)!), weight: wt,
                                   source: "app / self-reported", when: "before"))
            entries.append(WeighIn(at: DateParsing.isoString(cal.date(bySettingHour: 17, minute: 45, second: 0, of: d)!),
                                   weight: ((wt - sweat[i]) * 10).rounded() / 10, source: "app / self-reported", when: "after"))
        }
        log = entries.reversed()
        // A few practices already taken in the last week and a half (weekdays only).
        for back in 1...10 {
            let d = cal.date(byAdding: .day, value: -back, to: today)!
            let wd = cal.component(.weekday, from: d)
            guard (2...6).contains(wd) else { continue }
            var marks: [String: String] = [:]
            for (i, t) in Self.team.enumerated() { marks[t.name] = (i + back) % 7 == 0 ? "Absent" : "Present" }
            attendanceLog["practice|" + DayKey.key(d)] = (marks, "")
            if wd == 3 || wd == 5 { attendanceLog["power|" + DayKey.key(d)] = (marks, "") }
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "SampleSigned") { signed = "11/10/2026 7:15 PM" }   // -SampleSigned YES (screenshots)
        #endif
    }

    private func pause() async { try? await Task.sleep(nanoseconds: 350_000_000) }

    func home() async throws -> PortalData {
        if Self.coachMode { return try await coachHome() }
        await pause()
        let me = IronmanStats(name: name, present: "18", absent: "1", pct: "94.7%", openmat: "3", kids: "2", youth: "",
                              penalty: "0", total: "64", status: "ON TRACK", power: "4")
        return PortalData(
            role: "wrestler", email: Self.email, me: me,
            team: LooseDict(["Wrestlers Tracked": "28", "Practice Sessions": "19", "Open Mat Sessions": "6", "Current Ironmen": "11", "Team Practice %": "91.2%",
                             powerSessionsKey: "5"]),
            settings: LooseDict(["Minimum Practice Attendance %": "95", "Maximum Practice Absences": "3", "Practice points - Present": "3",
                                 "Open Mat points - Present": "2", "Kids Club Help points - Present": "2", "Kids Club Tournament - Absent penalty": "-10"]),
            updated: Date().formatted(date: .abbreviated, time: .shortened),
            descent: signed.isEmpty ? nil : descent, descentLocked: signed.isEmpty,
            descentNotes: LooseDict(["Minimum weight locked": "2/1/2027"]),
            weighIns: log, wrestlers: nil, descents: nil)
    }
    func weighIns() async throws -> [WeighIn] { await pause(); return log }
    func logWeighIn(_ weight: Double, when: WeighInWhen) async throws -> WeighIn {
        await pause()
        let w = WeighIn(at: DateParsing.isoString(Date()), weight: (weight * 10).rounded() / 10, source: "app / self-reported", when: when.rawValue)
        log.insert(w, at: 0)
        return w
    }
    func handbook() async throws -> HandbookInfo {
        await pause()
        return HandbookInfo(url: "https://example.com/team-handbook.pdf", season: "2026-27", name: name,
                            signed: signed, typed: signed.isEmpty ? "" : name)
    }
    func signHandbook(typed: String) async throws -> SignHandbookResult {
        await pause()
        guard typed.trimmingCharacters(in: .whitespaces).count >= 3 else { throw APIError(code: "failed", message: "Type your full name to sign.") }
        signed = Date().formatted(date: .numeric, time: .shortened)
        return SignHandbookResult(ok: true, signed: signed, already: false)
    }
    func weightPlan() async throws -> WeightPlanInfo {
        await pause()
        return WeightPlanInfo(classes: ["106","113","120","126","132","138","144","150","157","165","175","190","215","285"], name: name, plan: plan)
    }
    func saveWeightPlan(before: String, after: String, current: String, notes: String) async throws {
        await pause()
        plan = WeightClassPlan(saved: Date().formatted(date: .numeric, time: .shortened), before: before, after: after, current: current, notes: notes)
    }

    // MARK: Coach sample (launch with -SampleCoach YES). Made-up names, nothing real.

    static var coachMode: Bool { UserDefaults.standard.bool(forKey: "SampleCoach") }
    static let coachEmail = "coach@\(AppConfig.schoolDomain)"

    private static let team: [(name: String, start: Double, plan: Bool, points: Int, status: String)] = [
        ("Alex Carter", 133, true, 52, "ON TRACK"), ("Ben Doyle", 158, false, 47, "ON TRACK"),
        ("Cody Ellis", 121, true, 38, "OFF TRACK"), ("Drew Foster", 176, false, 61, "IRONMAN"),
        ("Eli Grant", 146, true, 44, "ON TRACK"), ("Finn Hayes", 113, false, 29, "OFF TRACK"),
        ("Gabe Irwin", 192, false, 55, "ON TRACK"), ("Hank Jensen", 139, true, 50, "ON TRACK"),
    ]

    private static func email(_ name: String) -> String {
        name.split(separator: " ").last!.lowercased() + "2028@" + AppConfig.schoolDomain
    }

    private func samplePlan(email: String, name: String, start: Double) -> DescentPlan {
        let classes = [106, 113, 120, 126, 132, 138, 144, 150, 157, 165, 175, 190, 215, 285]
        var steps: [DescentStep] = []
        var w = start
        for (k, s) in descent.steps.enumerated() {
            w = max(start * 0.93, w * 0.985)
            let ok = classes.filter { Double($0) >= w }.prefix(2).map(String.init)
            steps.append(DescentStep(label: "Week \(k + 1)", date: s.date, weight: (w * 100).rounded() / 100, classes: ok))
        }
        let minW = (start * 0.93 * 10).rounded() / 10
        let minClass = classes.first { Double($0) >= minW }.map(String.init) ?? ""
        return DescentPlan(email: email, name: name, perWeek: String(format: "%.1f", start * 0.015), minClass: minClass,
                           minWeight: String(minW), steps: steps)
    }

    func coachHome() async throws -> PortalData {
        await pause()
        let rows = Self.team.map { t in
            IronmanStats(name: t.name, present: "17", absent: t.status == "OFF TRACK" ? "3" : "1",
                         pct: t.status == "OFF TRACK" ? "85%" : "94.4%", openmat: "2", kids: "1", youth: "",
                         penalty: "0", total: String(t.points), status: t.status, power: String((t.points / 7) % 6))
        }
        let plans = Self.team.filter(\.plan).map { samplePlan(email: Self.email($0.name), name: $0.name, start: $0.start) }
        return PortalData(role: "coach", email: Self.coachEmail, me: nil,
                          team: LooseDict(["Wrestlers Tracked": "\(Self.team.count)", "Practice Sessions": "18", "Open Mat Sessions": "6",
                                           "Current Ironmen": "1", "Team Practice %": "92.1%", powerSessionsKey: "6"]),
                          settings: nil, updated: Date().formatted(date: .abbreviated, time: .shortened),
                          descent: nil, descentLocked: nil, descentNotes: LooseDict(["Minimum weight locked": "2/1/2027"]),
                          weighIns: nil, wrestlers: rows, descents: plans, classOverrides: classOverrides)
    }

    /// Sample coach weight-class overrides (school email -> class).
    private var classOverrides: [String: ClassOverride] = [:]

    func setWeightClass(email: String, weightClass: String) async throws -> SetWeightClassResult {
        await pause()
        guard weightClass.isEmpty || weightClasses.contains(weightClass) else { throw APIError(code: "failed", message: "Pick one of the weight classes.") }
        let stamp = Date().formatted(date: .numeric, time: .shortened)
        if weightClass.isEmpty { classOverrides[email] = nil }
        else { classOverrides[email] = ClassOverride(weightClass: weightClass, by: Self.coachEmail, updated: stamp) }
        return SetWeightClassResult(ok: true, weightClass: weightClass, by: Self.coachEmail, updated: stamp)
    }

    /// Sample team weigh-ins, made once so coach edits stick for the session.
    private var teamLog: [WrestlerWeighIns]?

    func teamWeighIns() async throws -> [WrestlerWeighIns] {
        await pause()
        if teamLog == nil { teamLog = makeTeamLog() }
        return teamLog!
    }

    func coachLogWeighIn(email: String, weight: Double, when: WeighInWhen) async throws -> WeighIn {
        await pause()
        guard let i = teamLog?.firstIndex(where: { $0.email == email }) else { throw APIError(code: "failed", message: "That wrestler has no school email on Portal Access yet.") }
        guard (70...350).contains(weight) else { throw APIError(code: "failed", message: "Enter their weight in pounds (between 70 and 350).") }
        let w = WeighIn(at: DateParsing.isoString(Date()), weight: (weight * 10).rounded() / 10, source: "coach / " + Self.coachEmail, when: when.rawValue)
        teamLog![i].weighIns.insert(w, at: 0)
        return w
    }

    func editWeighIn(email: String, at: String, weight: Double, when: WeighInWhen?) async throws -> WeighIn {
        await pause()
        guard let i = teamLog?.firstIndex(where: { $0.email == email }),
              let k = teamLog![i].weighIns.firstIndex(where: { $0.at == at }) else {
            throw APIError(code: "failed", message: "That weigh-in is no longer on the sheet. Pull to refresh.")
        }
        var w = teamLog![i].weighIns[k]
        let note = Date().formatted(date: .numeric, time: .shortened) + " by \(Self.coachEmail): was " + String(format: "%.1f", w.weight)
        w.edited = (w.edited ?? "").isEmpty ? note : w.edited! + "; " + note
        w.weight = (weight * 10).rounded() / 10
        if let when { w.when = when.rawValue }
        teamLog![i].weighIns[k] = w
        return w
    }

    func deleteWeighIn(email: String, at: String) async throws {
        await pause()
        guard let i = teamLog?.firstIndex(where: { $0.email == email }) else { return }
        teamLog![i].weighIns.removeAll { $0.at == at }
    }

    private func makeTeamLog() -> [WrestlerWeighIns] {
        let cal = Calendar.current
        return Self.team.enumerated().map { i, t in
            // Two wrestlers haven't logged anything yet; the rest log every other day or so.
            let count = (i == 5 || i == 6) ? 0 : 6 + (i % 4) * 2
            let entries: [WeighIn] = (0..<count).flatMap { k -> [WeighIn] in
                let daysAgo = (count - k) * 2 - (i % 2)
                let drift = Double(k) * (t.plan ? -0.45 : -0.1) + (k % 3 == 1 ? 0.6 : 0)
                let d = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
                let before = ((t.start + 1.5 + drift) * 10).rounded() / 10
                let loss = 2.2 + Double((i + k) % 5) * 0.35
                return [
                    WeighIn(at: DateParsing.isoString(cal.date(bySettingHour: 15, minute: 15 + i, second: 0, of: d)!),
                            weight: before, source: "app / self-reported", when: "before"),
                    WeighIn(at: DateParsing.isoString(cal.date(bySettingHour: 17, minute: 40 + i, second: 0, of: d)!),
                            weight: ((before - loss) * 10).rounded() / 10, source: "app / self-reported", when: "after"),
                ]
            }.reversed()
            return WrestlerWeighIns(email: Self.email(t.name), name: t.name, weighIns: entries)
        }
    }

    func handbookList() async throws -> HandbookList {
        await pause()
        let signed = Self.team.prefix(5).enumerated().map { i, t in HandbookSigner(name: t.name, when: "11/\(3 + i)/2026 7:1\(i) PM") }
        return HandbookList(season: "2026-27", url: "https://example.com/team-handbook.pdf",
                            signed: Array(signed), missing: Self.team.dropFirst(5).map(\.name))
    }

    func attendance(kind: AttendanceKind, date: String) async throws -> AttendanceSession {
        await pause()
        let saved = attendanceLog[kind.rawValue + "|" + date]
        let recent = attendanceLog.keys.filter { $0.hasPrefix(kind.rawValue + "|") }
            .map { String($0.dropFirst(kind.rawValue.count + 1)) }.sorted(by: >)
        return AttendanceSession(kind: kind.rawValue, date: date, exists: saved != nil, names: Self.team.map(\.name),
                                 marks: saved?.marks ?? [:], notes: saved?.notes ?? "", recent: Array(recent.prefix(12)))
    }

    func saveAttendance(kind: AttendanceKind, date: String, marks: [String: String], notes: String) async throws -> AttendanceSaveResult {
        await pause()
        guard DayKey.date(date) != nil else { throw APIError(code: "failed", message: "Pick a date.") }
        let key = kind.rawValue + "|" + date
        let updated = attendanceLog[key] != nil
        var clean: [String: String] = [:]
        for t in Self.team { clean[t.name] = marks[t.name] == "Present" ? "Present" : "Absent" }
        attendanceLog[key] = (clean, notes)
        return AttendanceSaveResult(updated: updated, present: clean.values.filter { $0 == "Present" }.count,
                                    total: Self.team.count, label: kind.label, date: date)
    }
}

import Foundation

/// The sheet sends display values (strings), but be forgiving about numbers too.
extension KeyedDecodingContainer {
    func loose(_ key: Key) -> String {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let d = try? decodeIfPresent(Double.self, forKey: key) {
            return d.rounded() == d ? String(Int(d)) : String(d)
        }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b ? "Yes" : "No" }
        return ""
    }
}

/// "95%" -> 95, "-5" -> -5, "" -> nil (same idea as num() in the portal page).
func number(_ s: String) -> Double? {
    let cleaned = s.filter { "0123456789.-".contains($0) }
    return Double(cleaned)
}

struct LooseDict: Decodable {
    var values: [String: String] = [:]
    init(_ v: [String: String] = [:]) { values = v }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        for k in c.allKeys { values[k.stringValue] = c.loose(k) }
    }
    subscript(_ k: String) -> String? { values[k] }
}

struct AnyKey: CodingKey {
    var stringValue: String; var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

struct IronmanStats: Decodable, Identifiable, Hashable {
    var id: String { name }
    var name, present, absent, pct, openmat, kids, youth, penalty, total, status: String
    /// Power/Speed sessions attended (tracked only, no points). Empty from older script versions.
    var power: String = ""

    enum K: String, CodingKey { case name, present, absent, pct, openmat, kids, youth, penalty, total, status, power }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        name = c.loose(.name); present = c.loose(.present); absent = c.loose(.absent); pct = c.loose(.pct)
        openmat = c.loose(.openmat); kids = c.loose(.kids); youth = c.loose(.youth)
        penalty = c.loose(.penalty); total = c.loose(.total); status = c.loose(.status); power = c.loose(.power)
    }
    init(name: String, present: String, absent: String, pct: String, openmat: String, kids: String, youth: String, penalty: String, total: String, status: String, power: String = "") {
        self.name = name; self.present = present; self.absent = absent; self.pct = pct; self.openmat = openmat
        self.kids = kids; self.youth = youth; self.penalty = penalty; self.total = total; self.status = status; self.power = power
    }
}

struct DescentStep: Decodable, Hashable, Identifiable {
    var id: String { date }
    var label: String
    var date: String          // "M/D/YYYY"
    var weight: Double        // lowest eligible weight that week
    var classes: [String]

    var day: Date? { DateParsing.mdy(date) }
}

struct DescentPlan: Decodable, Hashable {
    var email: String
    var name: String
    var perWeek: String
    var minClass: String
    var minWeight: String
    var steps: [DescentStep]

    enum K: String, CodingKey { case email, name, perWeek, minClass, minWeight, steps }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        email = c.loose(.email); name = c.loose(.name); perWeek = c.loose(.perWeek)
        minClass = c.loose(.minClass); minWeight = c.loose(.minWeight)
        steps = (try? c.decode([DescentStep].self, forKey: .steps)) ?? []
    }
    init(email: String, name: String, perWeek: String, minClass: String, minWeight: String, steps: [DescentStep]) {
        self.email = email; self.name = name; self.perWeek = perWeek; self.minClass = minClass; self.minWeight = minWeight; self.steps = steps
    }

    /// Index of this week's step: the last step dated on or before today (-1 = plan hasn't started). Same as dCur().
    func currentIndex(today: Date = Date()) -> Int {
        let t = Calendar.current.startOfDay(for: today)
        var i = -1
        for (k, s) in steps.enumerated() { if let d = s.day, d <= t { i = k } }
        return i
    }
    var currentStep: DescentStep? {
        guard !steps.isEmpty else { return nil }
        return steps[max(currentIndex(), 0)]
    }
    var nextStepDown: DescentStep? {
        let i = currentIndex()
        guard let cur = currentStep else { return nil }
        return steps.dropFirst(i + 1).first { $0.weight < cur.weight }
    }
}

/// When a weigh-in was taken. Wrestlers weigh before and after practice. Older rows have none (`nil`).
enum WeighInWhen: String, CaseIterable, Identifiable, Codable {
    case before, after, other
    var id: String { rawValue }
    var label: String { switch self { case .before: "Before practice"; case .after: "After practice"; case .other: "Other" } }
    var short: String { switch self { case .before: "Before"; case .after: "After"; case .other: "Other" } }
}

struct WeighIn: Decodable, Hashable, Identifiable {
    var id: String { at + String(weight) }
    var at: String            // ISO 8601 from the server
    var weight: Double
    var source: String
    var when: String? = nil   // "before" / "after" / "other" / "" (older rows)
    /// Set when a coach fixed this entry: "11/14/2026 9:30 AM by coach@…: was 120.0".
    var edited: String? = nil

    var date: Date { DateParsing.iso(at) ?? .distantPast }
    var kind: WeighInWhen? { when.flatMap(WeighInWhen.init(rawValue:)) }
    var isAfterPractice: Bool { kind == .after }
    /// "Before practice", "After practice", "Other", or "Self-reported" for older rows.
    var whenLabel: String { kind?.label ?? "Self-reported" }
    /// A coach punched this weight in (Source "coach / <email>"), rather than the wrestler.
    var isCoachEntry: Bool { source.lowercased().hasPrefix("coach") }
    var wasEdited: Bool { !(edited ?? "").isEmpty }
}

extension Array where Element == WeighIn {
    var newestFirst: [WeighIn] { sorted { $0.date > $1.date } }

    /// Latest weight to compare with the descent plan: before practice (or other), never the dehydrated after-practice one.
    var latestForPlan: WeighIn? { newestFirst.first { !$0.isAfterPractice } }

    /// The previous entry of the same kind (after vs. after; before/other vs. before/other), so sweat loss isn't a "change".
    func previous(sameKindAs w: WeighIn) -> WeighIn? {
        newestFirst.first { $0.date < w.date && $0.isAfterPractice == w.isAfterPractice }
    }

    /// For an after-practice entry: the before-practice entry earlier the same day.
    func beforePractice(matching w: WeighIn) -> WeighIn? {
        guard w.isAfterPractice else { return nil }
        let cal = Calendar.current
        return newestFirst.first { $0.kind == .before && $0.date < w.date && cal.isDate($0.date, inSameDayAs: w.date) }
    }

    /// Pounds lost at practice (positive = lost) for an after-practice entry with a same-day before.
    func practiceLoss(for w: WeighIn) -> Double? { beforePractice(matching: w).map { $0.weight - w.weight } }

    /// Suggested "when" for a new entry: After if there's a before-practice entry today and no after yet, else Before.
    func suggestedWhen(now: Date = Date()) -> WeighInWhen {
        let today = filter { Calendar.current.isDate($0.date, inSameDayAs: now) }
        return today.contains { $0.kind == .before } && !today.contains { $0.kind == .after } ? .after : .before
    }
}

struct PortalData: Decodable {
    var role: String
    var email: String
    var me: IronmanStats?
    var team: LooseDict?
    var settings: LooseDict?
    var updated: String?
    var descent: DescentPlan?
    var descentLocked: Bool?
    var descentNotes: LooseDict?
    var weighIns: [WeighIn]?
    var wrestlers: [IronmanStats]?   // coaches only
    var descents: [DescentPlan]?     // coaches only
    var classOverrides: [String: ClassOverride]?   // coaches only: school email -> class a coach set
    var weightClass: String?         // wrestlers: the class a coach set for them ("" = use the descent plan)

    var isCoach: Bool { role == "coach" }
    var hasDescentTab: Bool { descent != nil || descentLocked == true }
}

/// The 14 high school weight classes.
let weightClasses = ["106", "113", "120", "126", "132", "138", "144", "150", "157", "165", "175", "190", "215", "285"]

/// A coach's override of a wrestler's current weight class (Weight Classes tab).
struct ClassOverride: Decodable, Hashable {
    var weightClass: String
    var by: String
    var updated: String
    enum K: String, CodingKey { case weightClass, by, updated }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        weightClass = c.loose(.weightClass); by = c.loose(.by); updated = c.loose(.updated)
    }
    init(weightClass: String, by: String, updated: String) { self.weightClass = weightClass; self.by = by; self.updated = updated }
}
struct SetWeightClassResult: Decodable { var ok: Bool; var weightClass: String; var by: String?; var updated: String? }

/// Where a wrestler's current weight class comes from.
enum ClassSource { case coach, plan }

extension DescentPlan {
    /// This week's lowest eligible class from the plan (before the plan starts: its first week).
    var currentClass: String? { currentStep?.classes.first }
}

struct WeighInList: Decodable { var name: String; var weighIns: [WeighIn] }
struct LogWeighInResult: Decodable { var ok: Bool; var weighIn: WeighIn }
struct EditWeighInResult: Decodable { var ok: Bool; var changed: Bool; var weighIn: WeighIn }

struct HandbookInfo: Decodable {
    var url: String
    var season: String
    var name: String
    var signed: String
    var typed: String
    var isSigned: Bool { !signed.isEmpty }
}
struct SignHandbookResult: Decodable { var ok: Bool; var signed: String?; var already: Bool? }

struct WeightClassPlan: Decodable {
    var saved, before, after, current, notes: String
    enum K: String, CodingKey { case saved, before, after, current, notes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        saved = c.loose(.saved); before = c.loose(.before); after = c.loose(.after); current = c.loose(.current); notes = c.loose(.notes)
    }
    init(saved: String, before: String, after: String, current: String, notes: String) {
        self.saved = saved; self.before = before; self.after = after; self.current = current; self.notes = notes
    }
}
struct WeightPlanInfo: Decodable { var classes: [String]; var name: String; var plan: WeightClassPlan? }
struct OKResult: Decodable { var ok: Bool }

enum DateParsing {
    private static let mdyFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "M/d/yyyy"; return f
    }()
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func mdy(_ s: String) -> Date? { mdyFormatter.date(from: s.trimmingCharacters(in: .whitespaces)) }
    static func iso(_ s: String) -> Date? { isoFrac.date(from: s) ?? isoPlain.date(from: s) }
    static func isoString(_ d: Date) -> String { isoFrac.string(from: d) }
}

extension Double {
    /// 147 -> "147", 147.25 -> "147.3" (like dLb() in the portal)
    var lbs: String {
        let r = (self * 10).rounded() / 10
        return r.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(r)) : String(format: "%.1f", r)
    }
}

// MARK: - Coach-only data

struct WrestlerWeighIns: Decodable, Identifiable, Hashable {
    var id: String { email.isEmpty ? "name:" + name : email }
    var email: String
    var name: String
    var weighIns: [WeighIn]

    var sorted: [WeighIn] { weighIns.sorted { $0.date > $1.date } }
    var latest: WeighIn? { sorted.first }
    var previous: WeighIn? { latest.flatMap { weighIns.previous(sameKindAs: $0) } }
}
struct TeamWeighIns: Decodable { var wrestlers: [WrestlerWeighIns] }

struct HandbookSigner: Decodable, Hashable { var name: String; var when: String }
struct HandbookList: Decodable {
    var season: String
    var url: String
    var signed: [HandbookSigner]
    var missing: [String]
}

// MARK: Attendance (coaches). Same kinds and tabs as the portal's "Take Attendance".

/// Team snapshot key the script adds once the Power/Speed tab exists.
let powerSessionsKey = "Power/Speed Sessions"

enum AttendanceKind: String, CaseIterable, Identifiable {
    case practice, openmat, power, kidshelp, kidstourn
    var id: String { rawValue }
    /// Full name, as the portal shows it.
    var label: String {
        switch self {
        case .practice: "Practice"
        case .openmat: "Open Mat"
        case .power: "Power/Speed"
        case .kidshelp: "Youth Practice"
        case .kidstourn: "Youth Tournament"
        }
    }
    /// Shorter name for tight spots.
    var short: String {
        switch self {
        case .practice: "Practice"
        case .openmat: "Open Mat"
        case .power: "Power/Speed"
        case .kidshelp: "Youth Prac."
        case .kidstourn: "Youth Tourn."
        }
    }
    /// Tracked only: it doesn't add Ironman points.
    var tracksOnly: Bool { self == .power }
}

struct AttendanceSession: Decodable {
    var kind: String
    var date: String          // yyyy-MM-dd
    var exists: Bool          // a row for this date is already saved
    var names: [String]
    var marks: [String: String]   // "Present" / "Absent" / ""
    var notes: String
    var recent: [String]      // recent saved dates, newest first
}

struct AttendanceSaveResult: Decodable {
    var updated: Bool
    var present: Int
    var total: Int
    var label: String
    var date: String
}

enum DayKey {
    private static let f: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        return f
    }()
    static func key(_ d: Date) -> String { f.string(from: d) }
    static func date(_ k: String) -> Date? { f.date(from: k) }
    static func pretty(_ k: String) -> String {
        date(k)?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? k
    }
}

// MARK: Sorting names by last name ("Sam Smith" → Smith, Sam)

enum NameOrder {
    private static let suffixes: Set<String> = ["jr", "jr.", "sr", "sr.", "ii", "iii", "iv"]
    private static let particles: Set<String> = ["van", "von", "de", "del", "della", "der", "den", "la", "le", "di", "da", "st", "st."]

    /// "smith sam": last word (skipping Jr./III), then the rest, for sorting.
    static func key(_ name: String) -> String {
        var parts = name.split(separator: " ").map(String.init)
        if parts.count > 1, let l = parts.last, suffixes.contains(l.lowercased()) { parts.removeLast() }
        guard var last = parts.popLast() else { return name.lowercased() }
        // "Ana Van Dyke" sorts under V.
        while parts.count > 1, let w = parts.last, particles.contains(w.lowercased()) { last = parts.removeLast() + " " + last }
        return (last + " " + parts.joined(separator: " ")).lowercased()
    }

    static func less(_ a: String, _ b: String) -> Bool {
        let ka = key(a), kb = key(b)
        return ka == kb ? a < b : ka.localizedStandardCompare(kb) == .orderedAscending
    }
}

extension Array {
    func sortedByLastName(_ name: (Element) -> String) -> [Element] { sorted { NameOrder.less(name($0), name($1)) } }
}

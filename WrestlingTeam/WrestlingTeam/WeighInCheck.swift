import Foundation

/// Sanity checks before a weight is saved: blocks obvious typos, asks "is that a typo?" on big jumps. Nothing about the plan.
enum WeighInCheck {
    static let minWeight = 70.0, maxWeight = 350.0
    static let bigChangePct = 3.0          // vs. the last weigh-in

    enum Issue: Equatable {
        case invalid(String)               // can't save
        case warning(String)               // can save after confirming
        var isBlocking: Bool { if case .invalid = self { return true }; return false }
        var text: String { switch self { case .invalid(let s), .warning(let s): return s } }
    }

    /// Parses what they typed: "147.4", "147,4", " 147 lbs".
    static func parse(_ text: String) -> Double? {
        let t = text.replacingOccurrences(of: ",", with: ".").filter { "0123456789.".contains($0) }
        guard !t.isEmpty, t.filter({ $0 == "." }).count <= 1, let v = Double(t) else { return nil }
        return (v * 10).rounded() / 10
    }

    static let practiceLossPct = 5.0       // more than this lost in one practice is probably a typo

    /// `when`: before/after practice. After-practice weight is compared only with other after-practice weights and with
    /// that day's before-practice weight. `plan` is unused (kept so callers don't change).
    /// `coach`: a coach is logging for a wrestler, so the messages say "their" instead of "your".
    static func issues(for weight: Double?, when: WeighInWhen = .before, history: [WeighIn], plan: DescentPlan?, now: Date = Date(),
                       coach: Bool = false) -> [Issue] {
        let your = coach ? "their" : "your"
        guard let w = weight else { return [.invalid("Type \(your) weight in pounds, like 147.4.")] }
        guard w >= minWeight, w <= maxWeight else {
            return [.invalid("\(w.lbs) lbs doesn't look right. Enter \(your) weight in pounds (\(Int(minWeight))–\(Int(maxWeight))).")]
        }
        var out: [Issue] = []
        let past = history.filter { $0.date <= now }.newestFirst
        let isAfter = when == .after
        let cal = Calendar.current
        let day = { (d: Date) in d.formatted(.dateTime.month(.abbreviated).day()) }

        if isAfter, let before = past.first(where: { $0.kind == .before && cal.isDate($0.date, inSameDayAs: now) }) {
            // After practice: compare with today's before-practice weight.
            let loss = before.weight - w
            let pct = loss / before.weight * 100
            if pct > practiceLossPct {
                out.append(.warning("That's \(loss.lbs) lbs (\(String(format: "%.1f", pct))%) less than before practice today (\(before.weight.lbs)). Is that a typo?"))
            } else if pct < -1 {
                out.append(.warning("That's \((-loss).lbs) lbs more than before practice today (\(before.weight.lbs)). Is that a typo?"))
            }
        } else if let last = past.first(where: { $0.isAfterPractice == isAfter }) {
            let pct = (w - last.weight) / last.weight * 100
            if abs(pct) > bigChangePct {
                let dir = pct < 0 ? "lower" : "higher"
                let what = isAfter ? "\(your) last after-practice weigh-in" : "\(your) last weigh-in"
                out.append(.warning("That's \(abs(w - last.weight).lbs) lbs (\(String(format: "%.1f", abs(pct)))%) \(dir) than \(what) (\(last.weight.lbs) on \(day(last.date))). Is that a typo?"))
            }
        }
        // No weekly-drop or descent-plan warnings here: weights swing during the week, and the plan is a guide
        // for meet days that coaches adjust as the season goes. Coaches see who is well over
        // their plan on the coach side instead.
        return out
    }
}

private extension DescentPlan {
    func currentIndex(now: Date) -> Int { currentIndex(today: now) }
}

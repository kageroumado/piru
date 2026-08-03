import Foundation

// MARK: - Display helpers

extension SessionStateExport.Phase {
    /// Localized name — for the PDF (a visible document).
    var displayName: String {
        switch self {
        case .onset: String(localized: "Onset")
        case .comeup: String(localized: "Come-up")
        case .peak: String(localized: "Peak")
        case .offset: String(localized: "Offset")
        case .after: String(localized: "Afterglow")
        }
    }

    /// English name — for the Markdown data export (kept language-neutral, like
    /// the app's JSON/PsyLog exports, so it's a stable interchange format).
    var englishName: String {
        switch self {
        case .onset: "Onset"
        case .comeup: "Come-up"
        case .peak: "Peak"
        case .offset: "Offset"
        case .after: "Afterglow"
        }
    }
}

extension InteractionSeverity {
    var exportLabel: String {
        switch self {
        case .caution: String(localized: "Caution")
        case .unsafe: String(localized: "Unsafe")
        case .dangerous: String(localized: "Dangerous")
        }
    }

    var englishLabel: String {
        switch self {
        case .caution: "Caution"
        case .unsafe: "Unsafe"
        case .dangerous: "Dangerous"
        }
    }

    var exportSymbol: String {
        switch self {
        case .caution: "⚠️"
        case .unsafe: "🔶"
        case .dangerous: "🛑"
        }
    }
}

// MARK: - Markdown (English — a portable data export for AI agents / logs)

extension SessionStateExport {
    /// Render the snapshot as plain-text Markdown — the export a user hands to an
    /// AI agent or keeps as a portable log. Numbers and tables only, no graphics.
    /// Deliberately English (like the JSON/PsyLog exports) so it's a stable
    /// machine-readable format; the PDF is the localized, human-facing document.
    func markdown(locale: Locale = .current, calendar: Calendar = .current) -> String {
        let time = DateFormatter()
        time.locale = locale
        time.calendar = calendar
        time.timeStyle = .short
        time.dateStyle = .none

        let dayMonth = DateFormatter()
        dayMonth.locale = locale
        dayMonth.calendar = calendar
        dayMonth.setLocalizedDateFormatFromTemplate("MMMd")

        let full = DateFormatter()
        full.locale = locale
        full.calendar = calendar
        full.dateStyle = .medium
        full.timeStyle = .short

        let dateOnly = DateFormatter()
        dateOnly.locale = locale
        dateOnly.calendar = calendar
        dateOnly.dateStyle = .medium
        dateOnly.timeStyle = .none

        func clock(_ date: Date) -> String {
            if calendar.isDate(date, inSameDayAs: generatedAt) { return time.string(from: date) }
            return "\(time.string(from: date)) (\(dayMonth.string(from: date)))"
        }

        var out: [String] = []
        out.append("# Piru — " + (isLive ? "Session Snapshot" : "Session Report"))
        out.append("")
        if isLive {
            out.append("- **Generated:** \(full.string(from: generatedAt))")
            out.append("- **Session started:** \(clock(sessionStart)) (\(TimeInterval(generatedAt.timeIntervalSince(sessionStart)).durationHM) ago)")
            out.append("- **Active substances:** \(substances.count)")
        } else {
            out.append("- **Session:** \(dateOnly.string(from: sessionStart))")
            out.append("- **Doses:** \(substances.count)")
        }
        out.append("")

        if !interactions.isEmpty {
            for line in interactions {
                out.append("> \(line.severity.exportSymbol) **\(line.severity.englishLabel):** \(line.a) + \(line.b) — \(line.detail)")
            }
            out.append("")
        }

        out.append("## " + (isLive ? "Current state (subjective)" : "Doses"))
        out.append("")
        for s in substances {
            out.append("### \(s.name) — \(s.amount.doseFormatted) \(s.unit) \(s.route.lowercased())")
            if isLive {
                out.append("- Taken: \(clock(s.doseTimestamp)) (\(TimeInterval(generatedAt.timeIntervalSince(s.doseTimestamp)).durationHM) ago)")
                if let next = s.next {
                    out.append("- Phase: **\(s.phase.englishName)** — \(next.phase.englishName.lowercased()) in ~\(next.at.timeIntervalSince(generatedAt).durationHM), baseline \(clock(s.baselineAt))")
                } else {
                    out.append("- Phase: **\(s.phase.englishName)** — baseline \(clock(s.baselineAt))")
                }
                out.append("- Subjective intensity: **\(Int((s.intensity * 100).rounded()))%** of this dose's peak")
                out.append("- Curve progress: \(Int((s.progress * 100).rounded()))%")
            } else {
                out.append("- Taken: \(clock(s.doseTimestamp))")
            }
            out.append("")
        }

        out.append("## Elimination")
        out.append("")
        if isLive {
            out.append("| Substance | Half-life | In body now | Eliminated | 50% gone | 90% gone | Cleared |")
            out.append("|---|---|---|---|---|---|---|")
        } else {
            out.append("| Substance | Half-life | 50% gone | 90% gone | Cleared |")
            out.append("|---|---|---|---|---|")
        }
        for group in eliminations {
            out.append(eliminationRow(group, isLive: isLive, clock: clock))
        }
        out.append("")

        let detail = eliminations.filter { !$0.curve.isEmpty }
        if !detail.isEmpty {
            out.append("### Decay detail")
            out.append("")
            for group in detail {
                out.append("**\(group.name)**\(halfLifeSuffix(group)):")
                out.append("```")
                out.append(contentsOf: decayRows(group, clock: clock))
                out.append("```")
                out.append("")
            }
        }

        out.append("---")
        out.append("*Model estimates (one-compartment oral PK; alcohol zero-order). Individual clearance varies. Intensity is peak-relative. Not medical advice.*")
        return out.joined(separator: "\n")
    }

    private func countSuffix(_ group: EliminationGroup) -> String {
        group.doseCount > 1 ? " (×\(group.doseCount))" : ""
    }

    private func eliminationRow(_ group: EliminationGroup, isLive: Bool, clock: (Date) -> String) -> String {
        let name = group.name + countSuffix(group)
        /// Historical sessions drop the "in body now"/"eliminated" now-columns.
        func row(halfLife: String, inBody: String, eliminated: String, t50: String, t90: String, last: String) -> String {
            isLive
                ? "| \(name) | \(halfLife) | \(inBody) | \(eliminated) | \(t50) | \(t90) | \(last) |"
                : "| \(name) | \(halfLife) | \(t50) | \(t90) | \(last) |"
        }
        switch group.model {
        case let .firstOrder(hl, remaining, fraction, t50, t90, cleared):
            return row(halfLife: TimeInterval(hl * 60).durationHM, inBody: amount(remaining, group.unit), eliminated: "\(Int(((1 - fraction) * 100).rounded()))%", t50: clock(t50), t90: clock(t90), last: clock(cleared))
        case let .zeroOrder(grams, fraction, t50, t90, sober):
            return row(halfLife: "zero-order", inBody: amount(grams, "g"), eliminated: "\(Int(((1 - fraction) * 100).rounded()))%", t50: clock(t50), t90: clock(t90), last: clock(sober))
        case .unknown:
            return isLive ? "| \(name) | — | — | — | — | — | — |" : "| \(name) | — | — | — | — |"
        }
    }

    private func halfLifeSuffix(_ group: EliminationGroup) -> String {
        switch group.model {
        case let .firstOrder(hl, _, _, _, _, _): " (t½ \(TimeInterval(hl * 60).durationHM))"
        case .zeroOrder: " (zero-order)"
        case .unknown: ""
        }
    }

    private func decayRows(_ group: EliminationGroup, clock: (Date) -> String) -> [String] {
        let series = group.curve
        guard let peak = series.max(), peak > 0 else { return [] }
        let rows = 6
        var lines: [String] = []
        for i in 0 ... rows {
            let frac = Double(i) / Double(rows)
            let idx = min(series.count - 1, Int((frac * Double(series.count - 1)).rounded()))
            let minutes = frac * group.horizonMinutes
            let value = series[idx]
            let pct = Int((value / peak * 100).rounded())
            let tod = pad(TimeInterval(minutes * 60).durationHM, to: 10)
            let amt = padLeft(amount(value, group.unit), to: 9)
            let when = clock(group.groupStart.addingTimeInterval(minutes * 60))
            lines.append("t+\(tod)\(amt)  \(padLeft("\(pct)%", to: 4)) left   \(when)")
        }
        return lines
    }

    private func amount(_ value: Double, _ unit: String) -> String {
        let s = value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(s) \(unit)"
    }

    private func pad(_ s: String, to n: Int) -> String {
        s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
    }

    private func padLeft(_ s: String, to n: Int) -> String {
        s.count >= n ? s : String(repeating: " ", count: n - s.count) + s
    }
}

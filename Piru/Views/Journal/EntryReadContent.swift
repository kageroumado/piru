import SwiftUI
import TipKit

/// The read-mode body of ``EntryDetailView``: timeline hero, dose card, body
/// load, session context, journaling context, and the substance reference card.
struct EntryReadContent: View {
    let entry: DoseEntry
    let substance: Substance?
    let state: ActiveSubstanceState?
    let substanceColor: Color
    let colorMap: [String: Color]
    let sessionInteraction: InteractionResult?

    var body: some View {
        // Timeline graph — the session screen's bordered-chart treatment as a
        // headerless section of its own. List rows clip content to the section's
        // rounded-rect mask (no public opt-out), so the row carries enough
        // side/bottom margin that the flat chart's corners and pan track stay
        // clear of the corner rounding.
        if let state {
            Section {
                EntryTimelineGraph(state: state, chartFrame: true)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .popoverTip(GraphGestureTip())
            }
            .listSectionSpacing(12)
        } else {
            Section {
                Label("No pharmacokinetic data available for this substance and route.", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.vertical, 4)
            }
        }

        // The dose card — the graph's explainer. The chip cluster tucks into the
        // top-right corner concentrically, so the row's insets are the corner gap;
        // the leading text column keeps the standard 20pt.
        Section {
            EntryReadHero(entry: entry, substance: substance, state: state, substanceColor: substanceColor)
                .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20))
        }

        if isAlcoholEntry, UserProfileStore.shared.aldh2Deficient {
            AcetaldehydeCard(gramsEthanol: entryGramsEthanol)
        }

        if isOralCannabisEntry {
            ElevenHydroxyTHCCard()
        }

        // Body load, scoped to this dose — rendered only while the substance is
        // actually still in the body (a cleared dose answers the residual fact
        // via the hero's receipt line instead).
        SessionBodyLoadSection(
            entries: [entry],
            colorMap: colorMap,
            header: "In Your Body",
            activeOnly: true,
        )

        EntrySessionSection(entry: entry, sessionInteraction: sessionInteraction, colorMap: colorMap)

        EntryContextSection(entry: entry)

        EntryAboutSection(entry: entry, substance: substance)

        if resolvedDuration != nil {
            Section {
                NavigationLink(value: PushRoute.rampDown(timestamp: entry.timestamp, id: entry.id)) {
                    HStack {
                        Label("Comedown Alert", systemImage: "bell.badge")
                        Spacer()
                        if hasActiveRampDown {
                            Text("Active")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
            } footer: {
                Text("Get care reminders as effects fade — hydration, rest, and recovery tips.")
            }
        }
    }

    private var resolvedDuration: DurationProfile? {
        substance?.resolveDuration(for: entry.route)
    }

    private var hasActiveRampDown: Bool {
        RampDownScheduler.isActive(for: RampDownScheduler.entryKey(for: entry))
    }

    /// The substance is alcohol. Matched on the entry's own name so the
    /// acetaldehyde readout doesn't depend on substance resolution — the same
    /// predicate the zero-order timeline curve uses.
    private var isAlcoholEntry: Bool {
        let name = entry.substance.trimmingCharacters(in: .whitespaces).lowercased()
        return name == "alcohol" || name == "ethanol"
    }

    /// Cannabis taken **orally** (edible/oil/capsule) — the only place the
    /// 11-OH-THC first-pass story is the dominant, actionable effect. Inhaled
    /// cannabis is deliberately excluded (little first-pass conversion).
    private var isOralCannabisEntry: Bool {
        guard entry.route == .oral else { return false }
        let name = entry.substance.trimmingCharacters(in: .whitespaces).lowercased()
        return name == "cannabis" || name == "thc" || name == "marijuana" || name == "weed"
            || name == "edible" || name == "edibles" || name == "delta-9-thc" || name == "δ9-thc"
    }

    /// Grams of ethanol in this committed dose, when the unit is a mass.
    private var entryGramsEthanol: Double? {
        guard isAlcoholEntry else { return nil }
        switch entry.unit.trimmingCharacters(in: .whitespaces).lowercased() {
        case "g", "gram", "grams": return entry.amount
        case "mg", "milligram", "milligrams": return entry.amount / 1_000
        default: return nil
        }
    }
}

/// The dose card's headline: amount + chips + when + the live phase rail (or the
/// ended/cleared receipt). Minute ticks keep the relative time and phase current
/// while the screen stays open.
struct EntryReadHero: View {
    let entry: DoseEntry
    let substance: Substance?
    let state: ActiveSubstanceState?
    let substanceColor: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top) {
                        // The dose row's number treatment at hero scale — the tier
                        // is carried by the strength chip, not by tinting the figure.
                        MeasurementLabel(
                            amount: entry.amount,
                            unit: entry.unit,
                            numberStyle: .largeTitle,
                            numberWeight: .bold,
                            unitStyle: .title3,
                        )
                        Spacer(minLength: 8)
                        // Pulled 6pt past the text column so the capsules sit ~14pt
                        // off the card's top/trailing edges — concentric with its
                        // corner radius.
                        HStack(spacing: 6) {
                            if let saltForm = entry.saltForm {
                                // Chemical proper noun — not localized.
                                Text(saltForm)
                                    .heroChip(tint: substanceColor)
                            }
                            ROAPill(route: entry.route, size: .regular)
                            EntryStrengthChip(level: committedDoseLevel)
                        }
                        .padding(.trailing, -6)
                    }
                    Text(verbatim: "\(entry.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(EntryDoseFormat.relativeText(from: entry.timestamp, now: context.date))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                        .monospacedDigit()
                    if let drinkLine = byVolumeDisplayLine {
                        Label(drinkLine, systemImage: "wineglass")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(substanceColor)
                    }
                }

                EntryLiveStatus(state: state, now: context.date, clearedDate: clearedDate)
            }
        }
    }

    /// "IPA · 568 mL · 6% ABV" for a dose logged by volume, else nil.
    private var byVolumeDisplayLine: String? {
        guard let ml = entry.volumeML, let abv = entry.abv else { return nil }
        return ByVolumeBreadcrumb.make(name: entry.drinkName, volumeML: ml, abv: abv)
    }

    /// Dose level of the committed entry, classified against the ladder the dose
    /// was logged on — isomer included. Omitting the isomer here while the edit
    /// path includes it made the two modes disagree about the same dose.
    private var committedDoseLevel: DoseLevel? {
        guard let sub = substance, sub.displayClass.showsDoseLadder,
              let range = sub.doseRange(for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer) else { return nil }
        let refUnit = sub.unit(for: entry.route, saltForm: entry.saltForm, isomer: entry.isomer)
        let amount = entry.unit.caseInsensitiveCompare(refUnit) == .orderedSame
            ? entry.amount
            : (sub.convert(amount: entry.amount, from: entry.unit, toRoute: entry.route, saltForm: entry.saltForm) ?? entry.amount)
        return range.level(for: amount)
    }

    /// When this dose dropped below ~3% remaining — the same threshold the
    /// session's body-load projection uses. `nil` when no half-life is known.
    private var clearedDate: Date? {
        let halfLife = substance?.halfLifeMinutes ?? HalfLifeDatabase.halfLife(for: entry.substance)
        guard let halfLife, halfLife > 0 else { return nil }
        let ke = PKModel.ke(fromHalfLifeMinutes: halfLife)
        let ka = SubstanceEliminationCurve.estimateKa(for: entry.substance, ke: ke)
        let step = max(1.0, halfLife / 200)
        var minutes = 0.0
        var absorbed = false
        while minutes <= halfLife * 10 {
            let fraction = PKModel.fractionRemainingInBody(at: minutes, ke: ke, ka: ka)
            if fraction > 0.03 {
                absorbed = true
            } else if absorbed {
                return entry.timestamp.addingTimeInterval(minutes * 60)
            }
            minutes += step
        }
        return nil
    }
}

/// The tier badge ("light"/"common"/"heavy"), sized to match ``ROAPill``'s
/// `.regular` metrics so it aligns with the route pill in the hero.
struct EntryStrengthChip: View {
    let level: DoseLevel?

    var body: some View {
        if let level {
            Text(String(localized: level.displayName).lowercased())
                .heroChip(tint: level.labelColor)
        }
    }
}

/// The live phase rail while the dose is active, or the archival ended receipt
/// once effects have worn off — same slot, so the hero's shape doesn't reflow.
struct EntryLiveStatus: View {
    let state: ActiveSubstanceState?
    let now: Date
    let clearedDate: Date?

    var body: some View {
        if let state {
            let start = state.doseTimestamp
            let end = start.addingTimeInterval(state.totalMinutes * 60)
            if now >= start, now < end {
                DosePhaseProgressBar(state: state, now: now)
            } else if now >= end {
                EntryEndedReceipt(end: end, cleared: clearedDate)
            }
        }
    }
}

/// The archival answer once effects have worn off: when they ended, and — when
/// the PK model can say — when the body finished clearing the dose.
struct EntryEndedReceipt: View {
    let end: Date
    let cleared: Date?

    var body: some View {
        Label {
            if let cleared, cleared > end {
                Text("Effects ended ~\(SessionBodyLoadModel.milestoneText(end)) · cleared ~\(SessionBodyLoadModel.milestoneText(cleared))")
            } else {
                Text("Effects ended ~\(SessionBodyLoadModel.milestoneText(end))")
            }
        } icon: {
            Image(systemName: "checkmark.circle")
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryLabel)
    }
}

/// The dose's PK curve. Read mode draws it with the session screen's chart
/// frame; edit mode keeps it in a plain card, live-previewing the drafts.
struct EntryTimelineGraph: View {
    let state: ActiveSubstanceState
    let chartFrame: Bool

    var body: some View {
        TimelineGraphView(
            substances: [state],
            currentTime: .now,
            compact: false,
            chartFrame: chartFrame,
            synchronous: chartFrame,
        )
        .frame(height: chartFrame ? 176 : 160)
    }
}

/// Shared relative-time grammar for the entry-detail subviews — "44m ago" /
/// "3h 21m ago" / "2d ago", reusing the row grammar's localized keys.
enum EntryDoseFormat {
    static func relativeText(from date: Date, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        let totalMinutes = Int(elapsed / 60)
        guard totalMinutes >= 1 else { return String(localized: "just now") }
        let hours = totalMinutes / 60
        if hours >= 24 {
            return String(localized: "\(hours / 24)d ago")
        }
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return String(localized: "\(hours)h \(minutes)m ago")
        } else if hours > 0 {
            return String(localized: "\(hours)h ago")
        }
        return String(localized: "\(minutes)m ago")
    }
}

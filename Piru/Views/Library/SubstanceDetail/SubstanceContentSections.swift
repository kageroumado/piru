import SwiftData
import SwiftUI

/// Long-form overview prose (FreeOD Wiki), resolved locale-first by the store:
/// native Chinese when the app runs in Chinese, machine-translated English as a
/// fallback. Hidden when no source supplies an overview.
struct OverviewSection: View {
    /// Passed in (not read off `substance`) so its arrival survives the shell→
    /// full-record swap — see the note on ``SubstanceDetailLayout/overview``.
    let overview: SubstanceOverview?
    /// Only for the source deep link; the name it needs is already in the shell.
    let substance: Substance

    @State private var overviewExpanded = false

    /// Overview collapses to `collapsedLines` lines with a "Read more" when the
    /// prose exceeds `collapsedThreshold` characters (≈ that many lines), so
    /// short blurbs show in full with no toggle.
    private let collapsedLines = 5
    private let collapsedThreshold = 320

    var body: some View {
        if let overview, !overview.text.isEmpty {
            // Unlike the other folded blocks, the Overview reads better as a few
            // lines of prose with an inline "Read more" than as a closed
            // disclosure — you see what the substance *is* without a tap.
            let isLong = overview.text.count > collapsedThreshold
            Section {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Overview")
                        .sectionLabel()
                    Text(overview.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(isLong && !overviewExpanded ? collapsedLines : nil)
                        .fixedSize(horizontal: false, vertical: true)
                    if isLong {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { overviewExpanded.toggle() }
                        } label: {
                            Text(overviewExpanded ? "Read less" : "Read more")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    if overview.machineTranslated {
                        Label("Machine-translated from FreeOD Wiki", systemImage: "character.bubble")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    // Card and footer share one row — see ``DoseDurationSection``
                    // for why a peer row grows a hairline at some card heights.
                    SourceAttributionRow(
                        slug: overview.sourceSlug,
                        label: "Overview",
                        deepLink: SubstanceSourceLinks.deepLink(overview.sourceSlug, substance: substance),
                    )
                }
            }
        }
    }
}

/// The user's own dose history for this substance — a disclosure that expands to
/// the recent entries, with dose-range and most-common aggregates in the header.
/// Its own boundary so toggling it doesn't touch the rest of the screen.
struct HistorySection: View {
    let entries: [DoseEntry]
    let model: SubstanceDetailModel
    let defaultUnit: String

    @State private var showEntries = false
    @State private var showAllHistory = false

    var body: some View {
        let count = entries.count
        let stats = model.historyStats
        let unit = entries.first?.unit ?? defaultUnit
        let earliest = entries.last?.timestamp
        let latest = entries.first?.timestamp

        Section("Your History") {
            DisclosureGroup(isExpanded: $showEntries) {
                let displayEntries = showAllHistory ? entries : Array(entries.prefix(10))
                ForEach(displayEntries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("\(entry.amount.doseFormatted) \(entry.unit)")
                                .font(.subheadline)
                            Text(entry.route.localizedName)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                        Spacer()
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .captionSecondary()
                    }
                    .accessibilityElement(children: .combine)
                }
                if entries.count > 10, !showAllHistory {
                    Button {
                        showAllHistory = true
                    } label: {
                        Text("Show all \(entries.count) entries")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("^[\(count) entry](inflect: true)")
                            .font(.subheadline.weight(.medium))
                        if let earliest, let latest {
                            if Calendar.current.isDate(earliest, equalTo: latest, toGranularity: .month) {
                                Text(earliest.formatted(.dateTime.month(.wide).year()))
                                    .captionSecondary()
                            } else {
                                Text("\(earliest.formatted(.dateTime.month(.abbreviated).year())) – \(latest.formatted(.dateTime.month(.abbreviated).year()))")
                                    .captionSecondary()
                            }
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.xxs) {
                        if stats.minDose == stats.maxDose {
                            Text("\(stats.minDose.doseFormatted) \(unit)")
                                .font(.subheadline.weight(.medium))
                        } else {
                            Text("\(stats.minDose.doseFormatted) – \(stats.maxDose.doseFormatted) \(unit)")
                                .font(.subheadline.weight(.medium))
                        }
                        Text("Most common: \(stats.mostCommon.doseFormatted) \(unit)")
                            .captionSecondary()
                    }
                }
            }
        }
    }
}

/// The compound's framing — peptide protocol, research compound, prescription
/// medication, no-human-data — as **a chip in the header**, not a full-width
/// banner between the dose data and its meaning.
///
/// This was `StatusBanner`, a `Section`-sized `DetailBanner` with a title and a
/// two-line message. The design review's diagnosis was that three such banners
/// sat between the dose card and the first sentence that explained it, so the
/// framing cost a screen of scroll to say one word. Demoted here to a marker: the
/// title alone is the visible text, and the sentence that used to be the banner
/// body survives verbatim as the marker's accessibility label — same strings,
/// same translations, a tenth of the page.
struct SubstanceStatusMarker: View {
    /// The framings a compound can carry, in the order they're tested. Resolving
    /// is a `static` on the enum rather than an optional-returning `body`, so the
    /// header can `if let` it: a `View` that renders nothing still occupies a
    /// stack slot and takes its spacing with it.
    enum Kind {
        case peptideProtocol
        case researchCompound
        case prescription
        case medicalReference
        case limitedHumanData

        static func resolve(for substance: Substance) -> Kind? {
            if substance.usesPeptidePresentation { return .peptideProtocol }
            if substance.displayClass == .medicalRx || substance.displayClass == .nonRecreational {
                if substance.primaryProtocolDosing != nil { return .researchCompound }
                return substance.displayClass == .medicalRx ? .prescription : .medicalReference
            }
            // Only a genuinely thin entry (no dose, duration, *or* protocol data)
            // earns the "limited human data" framing, and only where the phrase can
            // be true of the molecule — an OTC compound reaches here without a
            // display-class banner of its own, and calcium is not thinly studied.
            // `mayReportLimitedData` is the shared gate the list badge also reads.
            if substance.isStub, substance.displayClass.mayReportLimitedData { return .limitedHumanData }
            return nil
        }

        var title: LocalizedStringResource {
            switch self {
            case .peptideProtocol: "Peptide — protocol reference"
            case .researchCompound: "Research / performance compound"
            case .prescription: "Prescription medication"
            case .medicalReference: "Medical information only"
            case .limitedHumanData: "Limited human data"
            }
        }

        /// The old banner body, kept as the marker's spoken label so nothing that
        /// was said before is lost — only its share of the screen.
        var detail: LocalizedStringResource {
            switch self {
            case .peptideProtocol:
                "Dosing shown reflects clinical or community research protocols, not medical advice. Peptides are injected from reconstituted powder — handle and store as noted below."
            case .researchCompound:
                "The protocol below reflects community or investigational use, not validated human dosing or medical advice. Many of these compounds are WADA-prohibited and lack human safety data."
            case .prescription, .medicalReference:
                "Dosing for this medication is determined by a healthcare provider and is not shown here. The information below is for recognition and reference only."
            case .limitedHumanData:
                "This compound has no validated human dose data. Information below is for reference only — see the linked sources for primary literature. Do not extrapolate doses from related compounds."
            }
        }

        var systemImage: String {
            switch self {
            case .peptideProtocol: "syringe.fill"
            case .researchCompound: "flask.fill"
            case .prescription, .medicalReference: "cross.case.fill"
            case .limitedHumanData: "exclamationmark.triangle.fill"
            }
        }

        /// The label and glyph *inside* the pill, so it is the `text` variant:
        /// an `accent` mark drawn on an `accent`-derived fill measures 2.82:1.
        var labelColor: Color {
            switch self {
            case .researchCompound, .limitedHumanData: .cautionText
            case .peptideProtocol, .prescription, .medicalReference: .infoText
            }
        }

        /// The mark color the pill's fill is derived from.
        var markColor: Color {
            switch self {
            case .researchCompound, .limitedHumanData: .cautionAccent
            case .peptideProtocol, .prescription, .medicalReference: .infoAccent
            }
        }
    }

    let kind: Kind

    var body: some View {
        Label(kind.title, systemImage: kind.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(kind.labelColor)
            .padding(.horizontal, 9)
            .padding(.vertical, Spacing.xs)
            // Matches ``CategoryChip``'s fill: 0.10 is the alpha the accent
            // scales' text variants are contrast-gated against.
            .background(kind.markColor.opacity(Theme.Opacity.tint), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(kind.detail))
    }
}

// `DetailBanner` — the shared full-width framing `Section` — lived here. It had
// exactly one client, `StatusBanner`, and both are gone: the framing is now
// ``SubstanceStatusMarker``, a chip in the header. Nothing else on the screen
// wants a banner, so the component went with its only caller rather than staying
// behind as an invitation to reintroduce one.

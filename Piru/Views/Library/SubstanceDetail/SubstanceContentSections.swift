import SwiftData
import SwiftUI

/// Long-form overview prose (FreeOD Wiki), resolved locale-first by the store:
/// native Chinese when the app runs in Chinese, machine-translated English as a
/// fallback. Hidden when no source supplies an overview.
struct OverviewSection: View {
    let substance: Substance

    @State private var overviewExpanded = false

    /// Overview collapses to `collapsedLines` lines with a "Read more" when the
    /// prose exceeds `collapsedThreshold` characters (≈ that many lines), so
    /// short blurbs show in full with no toggle.
    private let collapsedLines = 5
    private let collapsedThreshold = 320

    var body: some View {
        if let overview = substance.overview, !overview.text.isEmpty {
            // Unlike the other folded blocks, the Overview reads better as a few
            // lines of prose with an inline "Read more" than as a closed
            // disclosure — you see what the substance *is* without a tap.
            let isLong = overview.text.count > collapsedThreshold
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Overview", systemImage: "text.justify.left")
                        .font(.subheadline.weight(.semibold))
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.amount.doseFormatted) \(entry.unit)")
                                .font(.subheadline)
                            Text(entry.route.localizedName)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                        Spacer()
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("^[\(count) entry](inflect: true)")
                            .font(.subheadline.weight(.medium))
                        if let earliest, let latest {
                            if Calendar.current.isDate(earliest, equalTo: latest, toGranularity: .month) {
                                Text(earliest.formatted(.dateTime.month(.wide).year()))
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryLabel)
                            } else {
                                Text("\(earliest.formatted(.dateTime.month(.abbreviated).year())) – \(latest.formatted(.dateTime.month(.abbreviated).year()))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryLabel)
                            }
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if stats.minDose == stats.maxDose {
                            Text("\(stats.minDose.doseFormatted) \(unit)")
                                .font(.subheadline.weight(.medium))
                        } else {
                            Text("\(stats.minDose.doseFormatted) – \(stats.maxDose.doseFormatted) \(unit)")
                                .font(.subheadline.weight(.medium))
                        }
                        Text("Most common: \(stats.mostCommon.doseFormatted) \(unit)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
        }
    }
}

/// The contextual status banner shown above reference content. Peptides and
/// protocol-dosed performance compounds get framing appropriate to them instead
/// of the generic "ask your doctor" prescription notice.
struct StatusBanner: View {
    let substance: Substance

    var body: some View {
        if substance.usesPeptidePresentation {
            DetailBanner(
                title: "Peptide — protocol reference",
                systemImage: "syringe.fill",
                tint: .blue,
                message: "Dosing shown reflects clinical or community research protocols, not medical advice. Peptides are injected from reconstituted powder — handle and store as noted below.",
            )
        } else if substance.displayClass == .medicalRx || substance.displayClass == .nonRecreational {
            if substance.primaryProtocolDosing != nil {
                DetailBanner(
                    title: "Research / performance compound",
                    systemImage: "flask.fill",
                    tint: .orange,
                    message: "The protocol below reflects community or investigational use, not validated human dosing or medical advice. Many of these compounds are WADA-prohibited and lack human safety data.",
                )
            } else {
                DetailBanner(
                    title: substance.displayClass == .medicalRx ? "Prescription medication" : "Medical information only",
                    systemImage: "cross.case.fill",
                    tint: .blue,
                    message: "Dosing for this medication is determined by a healthcare provider and is not shown here. The information below is for recognition and reference only.",
                )
            }
        } else if substance.hasNoDoseData {
            DetailBanner(
                title: "Limited human data",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                message: "This compound has no validated human dose data. Information below is for reference only — see the linked sources for primary literature. Do not extrapolate doses from related compounds.",
            )
        }
    }
}

/// Plays along with an in-joke entry (PsychonautWiki's "🍰 Cake"). The emoji is
/// off the title now — so the gag lives here, deadpan, while making plain the
/// thing is fictional (this is a harm-reduction app; nobody should go sourcing
/// "Cake").
struct JokeBanner: View {
    let pictograph: String?

    var body: some View {
        if let emoji = pictograph {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(emoji)
                        Text("Made-up drug")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("A fictional drug from a 1997 TV satire on media drug panics — “Cake” isn’t real, and nothing below is either. It supposedly overstimulates “Shatner’s Bassoon,” the part of the brain that governs time. Made in Prague.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// The shared "framing" banner rendered as a `Section` — an icon-led title in a
/// tint color over a caption message. Used by ``StatusBanner`` for every
/// non-joke framing state.
struct DetailBanner: View {
    let title: LocalizedStringResource
    let systemImage: String
    let tint: Color
    let message: LocalizedStringResource

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }
}

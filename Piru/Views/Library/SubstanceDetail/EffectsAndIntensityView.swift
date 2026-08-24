import SwiftUI

/// The pushed "Effects & Intensity" screen, reached from the Effects section's
/// "Show All". Surfaces the drug.community experiential data — the circular
/// dose-intensity dial and the grouped, frequency-ranked reported effects —
/// while keeping first-hand reports as a locale-appropriate outbound link.
///
/// When a substance has no drug.community coverage it degrades to the vetted
/// PsychonautWiki effects grouped by category (the prior "All effects" view).
struct EffectsAndIntensityView: View {
    let substanceName: String
    /// Whether to offer an experience-reports link at all (gated upstream the
    /// same way the old Erowid link was).
    var showsExperienceReports = false

    @State private var model = EffectsIntensityModel()
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !model.reported.isEmpty {
                    reportedEffects
                } else if !model.fallbackGroups.isEmpty {
                    fallbackEffects
                }

                if showsExperienceReports, let link = reportsLink {
                    reportsCard(link)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Theme.background)
        .navigationTitle(Text("Effects", comment: "Screen title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: substanceName) { model.load(substanceName: substanceName) }
    }

    // MARK: reported effects (drug.community)

    private var reportedEffects: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.groupedReported, id: \.0) { domain, effects in
                Label {
                    Text(domain.localizedName)
                } icon: {
                    Circle().fill(domain.color).frame(width: 9, height: 9)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.top, domain == model.groupedReported.first?.0 ? 0 : 14)
                .padding(.bottom, 6)
                .padding(.leading, 4)

                VStack(spacing: 0) {
                    ForEach(effects) { effect in
                        EffectRow(effect: effect, maxFrequency: model.maxReportedFrequency)
                        if effect.id != effects.last?.id {
                            Divider().padding(.leading, 4)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .themeCard()
            }

            SourceAttributionRow(
                slug: "drug.community",
                label: "Effects",
                deepLink: model.drugCommunityDeepLink,
            )
            .padding(.horizontal, 2)
        }
    }

    // MARK: fallback (PsychonautWiki, no dc coverage)

    private var fallbackEffects: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(model.fallbackGroups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.category)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.secondaryLabel)
                        .padding(.bottom, 6)
                    VStack(spacing: 0) {
                        ForEach(group.effects, id: \.self) { effect in
                            HStack {
                                Text(effect).font(.body)
                                Spacer()
                            }
                            .padding(.vertical, 11)
                            if effect != group.effects.last {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .themeCard()
                }
            }
        }
    }

    // MARK: experience reports (locale-aware)

    private var isChineseLocale: Bool {
        locale.language.languageCode?.identifier == "zh"
    }

    /// Chinese users get native FreeODWiki reports; everyone else gets Erowid.
    private var reportsLink: (url: URL, chinese: Bool)? {
        if isChineseLocale, let slug = model.freeodwikiSlug,
           let url = AppSources.freeodwikiURL(slug: slug) {
            return (url, true)
        }
        if let url = AppSources.erowidSearchURL(substance: substanceName) {
            return (url, false)
        }
        return nil
    }

    private func reportsCard(_ link: (url: URL, chinese: Bool)) -> some View {
        Link(destination: link.url) {
            HStack(spacing: 12) {
                Image(systemName: "text.book.closed")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    if link.chinese {
                        Text("Read experience reports on FreeODWiki", comment: "Reports link, Chinese source")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Search experiences on Erowid", comment: "Reports link, Erowid")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("First-hand reports. Opens in your browser.", comment: "Reports link caption")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .padding(16)
            .themeCard()
        }
        .buttonStyle(.plain)
    }
}

/// One reported-effect row: name, a frequency bar, the report count, and the
/// dose band it emerges at.
private struct EffectRow: View {
    let effect: ReportedEffect
    let maxFrequency: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Text(effect.name)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 8)
                FrequencyBar(fraction: Double(effect.reportCount) / Double(max(maxFrequency, 1)))
                    .frame(width: 80)
                Text("\(effect.reportCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(width: 34, alignment: .trailing)
            }
            if let band = effect.emergesBandName {
                Text("Emerges at \(band)", comment: "Effect dose-emergence caption")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(effect.name)
        .accessibilityValue(Text("\(effect.reportCount) reports"))
    }
}

@MainActor
@Observable
final class EffectsIntensityModel {
    var bands: [SpectrumBand] = []
    var reported: [ReportedEffect] = []
    var fallbackGroups: [EffectGroup] = []
    var bandDoseText: [Int: String] = [:]
    var freeodwikiSlug: String?
    var drugCommunityDeepLink: URL?

    var maxReportedFrequency: Int {
        reported.map(\.reportCount).max() ?? 1
    }

    var groupedReported: [(EffectDomain, [ReportedEffect])] {
        EffectDomain.allCases.compactMap { domain in
            let items = reported.filter { $0.domain == domain }
            return items.isEmpty ? nil : (domain, items)
        }
    }

    func load(substanceName: String) {
        let store = SubstanceStore.shared
        bands = store.spectrumBands(forSubstanceName: substanceName)
        reported = store.reportedEffects(forSubstanceName: substanceName)
        if reported.isEmpty {
            fallbackGroups = store.effectsByCategory(forSubstanceName: substanceName)
        }
        let substance = SubstanceLibrary.resolveFull(substanceName)
        freeodwikiSlug = substance?.freeodwikiSlug
        if let substance {
            drugCommunityDeepLink = SubstanceSourceLinks.deepLink("drug.community", substance: substance)
            if let route = substance.routes.first(where: { $0.route == substance.defaultRoute })
                ?? substance.routes.first {
                bandDoseText = Self.bandDoseText(from: route.doses, unit: route.unit)
            }
        }
    }

    /// Map Piru's dose ladder onto the dial's six bands (Overdose has no range).
    static func bandDoseText(from doses: DoseRange, unit: String) -> [Int: String] {
        var out: [Int: String] = [:]
        func range(_ r: ClosedRange<Double>) -> String {
            "\(r.lowerBound.doseFormatted)–\(r.upperBound.doseFormatted) \(unit)"
        }
        if let t = doses.threshold { out[0] = "\(t.doseFormatted) \(unit)" }
        if let l = doses.light { out[1] = range(l) }
        if let c = doses.common { out[2] = range(c) }
        if let s = doses.strong { out[3] = range(s) }
        if let h = doses.heavy { out[4] = "\(h.doseFormatted)+ \(unit)" }
        return out
    }
}

extension ReportedEffect {
    /// Localized name of the dose band this effect emerges at, if known.
    var emergesBandName: String? {
        guard let band = emergesBand else { return nil }
        let keys = ["Threshold", "Light", "Common", "Strong", "Heavy", "Overdose"]
        guard band >= 0, band < keys.count else { return nil }
        let dummy = SpectrumBand(bandIndex: band, bandKey: keys[band], summary: "", topEffects: [], warnings: [])
        return dummy.localizedBandName
    }
}

extension EffectDomain {
    var localizedName: String {
        switch self {
        case .emotional: String(localized: "Emotional", comment: "Effect domain")
        case .cognitive: String(localized: "Cognitive", comment: "Effect domain")
        case .sensory: String(localized: "Sensory", comment: "Effect domain")
        case .physical: String(localized: "Physical", comment: "Effect domain")
        case .social: String(localized: "Social", comment: "Effect domain")
        }
    }

    var color: Color {
        switch self {
        case .emotional: Color(hex: "FF5A9E")
        case .cognitive: Color(hex: "4B8DFF")
        case .sensory: Color(hex: "E8940C")
        case .physical: Color(hex: "2FB56B")
        case .social: Color(hex: "A970FF")
        }
    }
}

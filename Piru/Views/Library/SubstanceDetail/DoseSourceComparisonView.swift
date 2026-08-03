import SwiftUI

/// **Dose & duration sources** — every source's ladder for one route, on one scale.
///
/// The dose card resolves a single ladder by source priority and shows one set of
/// numbers. That is the right default and it hides a real disagreement:
/// methamphetamine's oral "Common" is 15–30 mg to drug.community, 10–25 to
/// PsychonautWiki, 10–30 to TripSit and 10–20 to freeodwiki. None of them is
/// wrong — they measure different populations and intents — but a reader seeing
/// one number has no way to know the spread exists.
///
/// Reached by tapping the source line under the dose card. Read-only: changing
/// which source wins is a global preference (Settings → Source Priority), and
/// silently rewriting it from a substance screen would change every other
/// substance too.
struct DoseSourceComparisonView: View {
    let substanceName: String
    let route: RouteOfAdministration
    let accent: Color

    @State private var ladders: [SubstanceStore.SourceDoseLadder] = []
    @Environment(\.appNavigator) private var navigator

    /// The largest number any source names, so every bar shares one scale — the
    /// whole point is that the bars are comparable.
    private var scaleMax: Double {
        let values = ladders.flatMap { ladder -> [Double] in
            let d = ladder.doses
            return [
                d.threshold,
                d.light?.upperBound,
                d.common?.upperBound,
                d.strong?.upperBound,
                d.heavy,
            ].compactMap(\.self)
        }
        return max(values.max() ?? 1, 0.0001)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ladders) { ladder in
                        LadderRow(ladder: ladder, scaleMax: scaleMax, accent: accent)
                    }
                } header: {
                    Text("\(route.localizedName) · \(ladders.count) sources")
                } footer: {
                    // This footer names the control and nothing else. Do not add a
                    // sentence explaining why the ladders differ — nothing in the
                    // data records who a source measured or what for, so any such
                    // reason is invented. "These sources disagree" is equally
                    // unsupported: for many substances the ladders above are
                    // identical. The reader can see the numbers.
                    Text(
                        "Piru shows the source you rank highest — change that in Settings › Source Priority.",
                        comment: "Dose source comparison footer",
                    )
                }

                Section {
                    Button {
                        navigator.present(.sourcePriority)
                    } label: {
                        Label("Source Priority", systemImage: "list.number")
                    }
                }
            }
            .navigationTitle(Text("Dose sources", comment: "Screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        navigator.dismiss()
                    } label: {
                        Text("Done")
                    }
                }
            }
        }
        .task(id: substanceName) {
            ladders = SubstanceStore.shared.doseLadders(forSubstanceName: substanceName, route: route)
        }
    }
}

/// One source: its name, its Common range as the headline number, and the five
/// tiers drawn as a stacked bar on the shared scale.
private struct LadderRow: View {
    let ladder: SubstanceStore.SourceDoseLadder
    let scaleMax: Double
    let accent: Color

    private static let tierColors: [Color] = [
        .Dose.Threshold.accent, .Dose.Light.accent, .Dose.Common.accent,
        .Dose.Strong.accent, .Dose.Heavy.accent,
    ]

    /// Tier spans as `(startFraction, endFraction, color)` on the shared scale.
    /// A tier a source didn't supply simply contributes nothing, so a sparse
    /// ladder reads as sparse rather than as a different shape.
    private var segments: [(start: Double, end: Double, color: Color)] {
        let d = ladder.doses
        var out: [(Double, Double, Color)] = []
        func add(_ lower: Double?, _ upper: Double?, _ index: Int) {
            guard let lower, let upper, upper > lower else { return }
            out.append((lower / scaleMax, upper / scaleMax, Self.tierColors[index]))
        }
        if let t = d.threshold, let lightLower = d.light?.lowerBound ?? d.common?.lowerBound {
            add(t, max(lightLower, t), 0)
        }
        add(d.light?.lowerBound, d.light?.upperBound, 1)
        add(d.common?.lowerBound, d.common?.upperBound, 2)
        add(d.strong?.lowerBound, d.strong?.upperBound, 3)
        if let heavy = d.heavy {
            add(heavy, scaleMax, 4)
        }
        return out
    }

    /// The source's human name, not its slug — the same resolution the
    /// attribution rows use, so "psychonautwiki" reads as "PsychonautWiki".
    private var displayName: String {
        AppSources.slugToName[ladder.sourceSlug]
            ?? SubstanceStore.shared.sourceDisplayName(forSlug: ladder.sourceSlug)
    }

    private var commonText: String {
        guard let common = ladder.doses.common else { return "—" }
        return "\(common.lowerBound.doseFormatted)–\(common.upperBound.doseFormatted) \(ladder.unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                if ladder.isActive {
                    Text("In use", comment: "Badge on the source currently supplying the dose ladder")
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(accent.opacity(0.12), in: Capsule())
                }
                Spacer(minLength: 8)
                Text(commonText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryLabel)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Capsule()
                            .fill(segment.color)
                            .frame(width: max(2, geo.size.width * (segment.end - segment.start)))
                            .offset(x: geo.size.width * segment.start)
                    }
                }
            }
            .frame(height: 10)

            HStack {
                Text("0")
                Spacer()
                Text("\(scaleMax.doseFormatted) \(ladder.unit)")
            }
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(displayName))
        .accessibilityValue(Text(commonText))
    }
}

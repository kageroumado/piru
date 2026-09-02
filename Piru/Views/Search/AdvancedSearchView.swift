import SwiftUI

/// Pharma-nerd surface: query the substance store by receptor target, Ki
/// threshold, and substance-name fragment. Each result row carries explicit
/// source attribution (slug + DOI/PMID when known) so users can apply their
/// own trust filter on top of the global source priority.
///
/// Lives in the Tools tab. Hidden behind a tier check in the entry point so
/// casual users don't stumble into it.
struct AdvancedSearchView: View {
    @State private var availableTargets: [(target: String, substanceCount: Int)] = []
    @State private var selectedTarget: String?
    @State private var kiCeilingNm: Double = 1_000
    @State private var kiCeilingEnabled = false
    @State private var substanceQuery = ""
    @State private var results: [BindingHit] = []

    private let kiSliderRange: ClosedRange<Double> = 1 ... 10_000

    var body: some View {
        List {
            filterSection
            resultsSection
        }
        .task { reloadTargets() }
        // Debounce every filter change through one task so dragging the Ki
        // slider (10 nM steps → up to ~1000 events) doesn't fire a SQLite scan
        // per step. Skips the scan entirely when no filter is active, preserving
        // the old behavior of not auto-running an unfiltered query on appear.
        .task(id: queryParams) {
            guard queryParams.isActive else {
                results = []
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            runQuery()
        }
    }

    /// The fields the bindings query depends on, folded into one `Equatable`
    /// value so a single `.task(id:)` debounces all of them.
    private struct QueryParams: Equatable {
        let target: String?
        let kiAtMost: Double?
        let contains: String

        var isActive: Bool {
            target != nil || kiAtMost != nil || !contains.isEmpty
        }
    }

    private var queryParams: QueryParams {
        QueryParams(
            target: selectedTarget,
            kiAtMost: kiCeilingEnabled ? kiCeilingNm : nil,
            contains: substanceQuery.trimmingCharacters(in: .whitespacesAndNewlines),
        )
    }

    private var filterSection: some View {
        Section {
            TextField("Substance contains…", text: $substanceQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Picker("Receptor target", selection: $selectedTarget) {
                Text("Any").tag(String?.none)
                ForEach(availableTargets, id: \.target) { entry in
                    Text("\(entry.target) (\(entry.substanceCount))")
                        .tag(String?(entry.target))
                }
            }

            Toggle("Ki ≤ \(Int(kiCeilingNm)) nM", isOn: $kiCeilingEnabled)
            if kiCeilingEnabled {
                Slider(value: $kiCeilingNm, in: kiSliderRange, step: 10)
                    .accessibilityValue(Text("\(Int(kiCeilingNm)) nM"))
            }
        } header: {
            Text("Filters")
        } footer: {
            Text("Lower Ki means tighter binding. Affinity below ~100 nM is usually considered high.")
        }
    }

    private var resultsSection: some View {
        Section {
            if results.isEmpty {
                Text("No bindings match these filters.")
                    .foregroundStyle(Theme.secondaryLabel)
            } else {
                ForEach(results) { hit in
                    BindingHitRow(hit: hit)
                }
            }
        } header: {
            Text("Results (\(results.count))")
        }
    }

    private func reloadTargets() {
        availableTargets = SubstanceStore.shared.availableBindingTargets()
    }

    /// The bindings query is a synchronous SQLite read — runs in <10 ms even
    /// for unfiltered scans. No loading state needed; if that ever changes,
    /// move the call into a `Task` and re-introduce a progress indicator.
    private func runQuery() {
        let p = queryParams
        results = SubstanceStore.shared.bindings(
            target: p.target,
            kiNmAtMost: p.kiAtMost,
            substanceContains: p.contains.isEmpty ? nil : p.contains,
        )
    }
}

private struct BindingHitRow: View {
    let hit: BindingHit

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(hit.substanceName)
                    .cardTitle()
                Spacer()
                if let ki = hit.kiNm {
                    Text("Ki \(formatNm(ki)) nM")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                } else if let ec = hit.ec50Nm {
                    Text("EC50 \(formatNm(ec)) nM")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            HStack(spacing: Spacing.sm) {
                Text(hit.target)
                    .font(.caption.monospaced())
                Middot()
                Text(hit.action)
                if let species = hit.species, !species.isEmpty {
                    Middot()
                    Text(species)
                        .italic()
                }
            }
            .captionSecondary()
            HStack(spacing: Spacing.sm) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(hit.sourceSlug)
                    .font(.caption2.monospaced())
                if let pmid = hit.pmid {
                    Text("· PMID \(pmid)").font(.caption2)
                } else if let doi = hit.doi, !doi.isEmpty {
                    Text("· DOI").font(.caption2)
                }
            }
            .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, Spacing.xxs)
    }
}

#Preview {
    NavigationStack { AdvancedSearchView() }
}

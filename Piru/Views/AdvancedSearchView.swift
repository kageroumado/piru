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
    @State private var results: [SubstanceStore.BindingHit] = []

    private let kiSliderRange: ClosedRange<Double> = 1 ... 10_000

    var body: some View {
        List {
            filterSection
            resultsSection
        }
        .task { reloadTargets() }
        .onChange(of: selectedTarget) { _, _ in runQuery() }
        .onChange(of: kiCeilingEnabled) { _, _ in runQuery() }
        .onChange(of: kiCeilingNm) { _, _ in runQuery() }
        .onChange(of: substanceQuery) { _, _ in runQuery() }
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
                    .foregroundStyle(.secondary)
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
        let target = selectedTarget
        let kiAtMost = kiCeilingEnabled ? kiCeilingNm : nil
        let q = substanceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        results = SubstanceStore.shared.bindings(
            target: target,
            kiNmAtMost: kiAtMost,
            substanceContains: q.isEmpty ? nil : q,
        )
    }
}

private struct BindingHitRow: View {
    let hit: SubstanceStore.BindingHit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(hit.substanceName)
                    .font(.headline)
                Spacer()
                if let ki = hit.kiNm {
                    Text("Ki \(formatNm(ki)) nM")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if let ec = hit.ec50Nm {
                    Text("EC50 \(formatNm(ec)) nM")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Text(hit.target)
                    .font(.caption.monospaced())
                Text("·")
                Text(hit.action)
                if let species = hit.species, !species.isEmpty {
                    Text("·")
                    Text(species)
                        .italic()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption2)
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
        .padding(.vertical, 2)
    }

    private func formatNm(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }
}

#Preview {
    NavigationStack { AdvancedSearchView() }
}

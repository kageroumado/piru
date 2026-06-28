import SwiftUI

/// A plain-language "what does this mean?" bottom sheet for the dense pharmacology cards. Surfaced from an
/// (i) button in a card's header; explains each term in simple vocabulary (and parks the scientific symbol
/// here, off the card face). iOS 26 system sheet — medium detent, drag indicator, Done button.
struct PharmacologyGlossarySheet: View {
    enum Topic: String, Identifiable {
        case pharmacokinetics
        case receptor
        var id: String {
            rawValue
        }
    }

    let topic: Topic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(entry.term)
                                    .font(.subheadline.weight(.semibold))
                                if let symbol = entry.symbol {
                                    Text(symbol)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(Theme.secondaryLabel)
                                }
                            }
                            Text(entry.explanation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                } footer: {
                    Text(footer)
                }
            }
            .listRowBackground(Theme.cardBackground)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var title: LocalizedStringResource {
        switch topic {
        case .pharmacokinetics: "Pharmacokinetics"
        case .receptor: "Receptor data"
        }
    }

    private var footer: LocalizedStringResource {
        switch topic {
        case .pharmacokinetics:
            "These are population averages from research — your own values vary with genetics, body size, and how the drug is taken."
        case .receptor:
            "Stronger doesn't mean more dangerous — it's just how tightly the drug grips that one target in the lab."
        }
    }

    private struct Entry: Identifiable {
        let id: String
        let term: LocalizedStringResource
        let symbol: String?
        let explanation: LocalizedStringResource
    }

    private var entries: [Entry] {
        switch topic {
        case .pharmacokinetics: Self.pkEntries
        case .receptor: Self.receptorEntries
        }
    }

    private static let pkEntries: [Entry] = [
        .init(
            id: "F",
            term: "Bioavailability",
            symbol: "F",
            explanation: "How much of a dose actually reaches your bloodstream. Swallowing a drug usually delivers less than injecting it.",
        ),
        .init(
            id: "Tmax",
            term: "Time to peak",
            symbol: "Tmax",
            explanation: "How long after taking it the level in your blood is highest — roughly when effects peak.",
        ),
        .init(
            id: "t12",
            term: "Half-life",
            symbol: "t½",
            explanation: "The time for your body to clear half of what's left. It takes about five half-lives to clear almost all of it.",
        ),
        .init(
            id: "PPB",
            term: "Protein binding",
            symbol: "PPB",
            explanation: "The share that rides along stuck to blood proteins. Only the unbound rest is free to act.",
        ),
        .init(
            id: "Vd",
            term: "Distribution",
            symbol: "Vd",
            explanation: "How widely the drug spreads from blood into the rest of the body. A bigger number means it soaks into tissues rather than staying in the blood.",
        ),
        .init(
            id: "CL",
            term: "Clearance",
            symbol: "CL",
            explanation: "How fast your body removes the drug, mostly via the liver and kidneys.",
        ),
        .init(
            id: "Cmax",
            term: "Peak level",
            symbol: "Cmax",
            explanation: "The highest concentration reached in the blood after a dose.",
        ),
    ]

    private static let receptorEntries: [Entry] = [
        .init(
            id: "dots",
            term: "Strength dots",
            symbol: nil,
            explanation: "A quick read of how potent the drug is at that target — three dots is strong, one is weak. The same scale is used on the Mechanism card.",
        ),
        .init(
            id: "binding",
            term: "Binding",
            symbol: "Ki",
            explanation: "Measures how tightly the drug grips the target (Ki). A smaller number means a tighter grip.",
        ),
        .init(
            id: "functional",
            term: "Functional",
            symbol: "EC50 / IC50",
            explanation: "Measures the dose needed to actually switch the target on or block it, rather than just stick to it. Also smaller = more potent.",
        ),
        .init(
            id: "nM",
            term: "nM (nanomolar)",
            symbol: nil,
            explanation: "The concentration unit these values use. Lower numbers always mean the drug works at smaller amounts.",
        ),
        .init(
            id: "species",
            term: "Human vs animal",
            symbol: nil,
            explanation: "Many values come from animal or lab-dish studies. Human data is the most reliable — the source tag tells you which it is.",
        ),
    ]
}

import SwiftData
import SwiftUI

/// What the "did it work?" answers line up with — the interpretive half of the
/// session note, kept here so the note itself stays a record.
///
/// Says plainly when there is not enough yet, and never turns an observation
/// into an instruction: *"your doses before 8:10 read 'about right' more often
/// than your later ones"*, never *"take it before 8."*
struct FeltPatternsView: View {
    @Query private var sessions: [Session]
    @Query(sort: \DoseEntry.timestamp, order: .reverse) private var entries: [DoseEntry]

    @State private var model = FeltPatternsModel()

    var body: some View {
        List {
            Group {
                if !model.isLoaded {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                } else if model.ratedDayCount == 0 {
                    emptySection
                } else {
                    headerSection
                    countSection
                    if model.notable.isEmpty, model.flat.isEmpty {
                        notEnoughSection
                    }
                    ForEach(model.notable) { SplitSection(split: $0, isNotable: true) }
                    ForEach(model.flat) { SplitSection(split: $0, isNotable: false) }
                    caveatSection
                }
            }
            .listRowBackground(CardBackground())
        }
        .insetGroupedListStyle()
        .themedPage()
        .task(id: DoseLogService.shared.revision) {
            await SubstanceStore.shared.ensureAllLoaded()
            model.recompute(sessions: sessions, entries: entries)
        }
    }

    // MARK: - Sections

    /// Tagged like Effect Estimates: the method is a comparison of one
    /// person's own days, and the badge says so before the first number does.
    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Your days, side by side")
                        .sectionLabel()
                    Text("Each comparison cuts your rated days on one thing at a time and counts how often the dose read \"about right\" or better.")
                        .captionSecondary()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ExperimentalTag()
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private var emptySection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Nothing rated yet")
                    .sectionLabel()
                Text("A check-in asks whether a dose worked the way it usually does. Once a few days carry an answer, this screen shows what they line up with.")
                    .captionSecondary()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private var countSection: some View {
        Section {
            LabeledContent("Days rated") {
                Text("\(model.ratedDayCount)")
                    .monospacedDigit()
            }
            LabeledContent("Substances") {
                Text("\(model.substanceCount)")
                    .monospacedDigit()
            }
        }
    }

    private var notEnoughSection: some View {
        Section {
            Text("Not enough yet. A comparison needs at least \(FeltPatternsModel.minimumPerSide) rated days on each side before it means anything — below that, one bad week writes the headline.")
                .captionSecondary()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Spacing.xs)
        }
    }

    private var caveatSection: some View {
        Section {
            Text("These are your own days next to each other — one person, no control group. A difference here is something to notice, not a reason.")
                .captionSecondary()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Spacing.xs)
        }
    }
}

// MARK: - One split

/// Two sides of one variable, each as a count and a bar. The sentence states
/// the comparison; it never states what to do about it.
private struct SplitSection: View {
    let split: FeltPatternsModel.Split
    let isNotable: Bool

    var body: some View {
        Section {
            SplitSideRow(label: split.lowLabel, tally: split.low, isNotable: isNotable)
            SplitSideRow(label: split.highLabel, tally: split.high, isNotable: isNotable)
        } header: {
            HStack {
                Label(split.variable.title, systemImage: split.variable.icon)
                Spacer()
                Text(split.substance)
                    .textCase(nil)
            }
        } footer: {
            if !isNotable {
                Text("Both sides read about the same.")
            }
        }
    }
}

private struct SplitSideRow: View {
    let label: String
    let tally: FeltPatternsModel.Tally
    let isNotable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text("\(tally.asExpected) of \(tally.days)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryLabel)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.accent.opacity(Theme.Opacity.tint))
                    Capsule()
                        .fill(isNotable ? Theme.accent : Color.secondary)
                        .frame(width: max(2, geo.size.width * tally.fraction))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(tally.asExpected) of \(tally.days) days about right or better"))
    }
}

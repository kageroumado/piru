import SwiftData
import SwiftUI

struct ComedownGuideView: View {
    @Query private var recentEntries: [DoseEntry]

    /// Resolved in the `.task`, not per body pass: a per-substance resolve
    /// over the dose log is too expensive to run on every body evaluation.
    @State private var recentCategories: [SubstanceCategory] = []

    init() {
        let cutoff = Date.now.addingTimeInterval(-48 * 3_600)
        _recentEntries = Query(
            filter: #Predicate<DoseEntry> { $0.timestamp >= cutoff },
            sort: \DoseEntry.timestamp,
            order: .reverse,
        )
    }

    var body: some View {
        List {
            Group {
                aboutSection

                if !recentCategories.isEmpty {
                    Section("From Your Last 48 Hours") {
                        ForEach(recentCategories, id: \.self) { cat in
                            ComedownCategoryDisclosure(category: cat)
                        }
                    }
                }

                Section("All Categories") {
                    ForEach(ComedownGuide.guidedCategories.filter { !recentCategories.contains($0) }, id: \.self) { cat in
                        ComedownCategoryDisclosure(category: cat)
                    }
                }

                generalSection
            }
            .listRowBackground(CardBackground())
        }
        .insetGroupedListStyle()
        .themedPage()
        .task(id: DoseLogService.shared.revision) {
            await SubstanceStore.shared.ensureAllLoaded()
            // The query already bounds entries to the 48 h window.
            recentCategories = ComedownGuide.recentGuidedCategories(in: recentEntries, cutoff: .distantPast)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("What is this?", systemImage: "heart.text.clipboard")
                    .sectionLabel()
                Text("What sources report about the hours after each class wears off. It describes the class, never your condition.")
                    .captionSecondary()
                Text("If someone is hard to wake, breathing slowly, overheating or having a seizure, call emergency services.")
                    .captionSecondary()
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    // MARK: - General Tips

    private var generalSection: some View {
        Section("Universal Recovery Basics") {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                tipRow(icon: "drop.fill", color: .blue, text: "Hydrate: water or electrolyte drinks, sip steadily")
                tipRow(icon: "fork.knife", color: .orange, text: "Eat something nutritious: protein, carbs, and fruit")
                tipRow(icon: "bed.double.fill", color: .indigo, text: "Rest when your body asks for it")
                tipRow(icon: "sun.max.fill", color: .yellow, text: "Fresh air and gentle light")
                tipRow(icon: "figure.walk", color: .green, text: "Light movement or stretching, nothing intense")
                tipRow(icon: "iphone.slash", color: .gray, text: "Put the phone down. Screens can amplify restlessness")
                tipRow(icon: "person.2.fill", color: .pink, text: "Reach out to someone you trust if you feel overwhelmed")
            }
            .font(.caption)
            .padding(.vertical, Spacing.xs)
        }
    }

    private func tipRow(icon: String, color: Color, text: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(Theme.secondaryLabel)
        }
    }
}

/// A single comedown category as a fold-open row: the category icon + name, its
/// per-category recovery tips revealed on tap. Shared by ``ComedownGuideView``'s
/// category lists and the session detail's Recovery section so both show the
/// identical rows. Owns its own expansion state.
struct ComedownCategoryDisclosure: View {
    let category: SubstanceCategory
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            HStack(spacing: Spacing.lg) {
                Image(systemName: category.icon)
                    .foregroundStyle(category.labelColor)
                    .accessibilityHidden(true)
                    .frame(width: 24)
                Text(category.displayName)
                    .font(.body)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let guide = ComedownGuide.guide(for: category)
        VStack(alignment: .leading, spacing: Spacing.xl) {
            tipGroup("What's happening", items: guide.whatsHappening)
            tipGroup("Right now", items: guide.rightNow)
            tipGroup("Over the next hours", items: guide.nextHours)
            tipGroup("What to avoid", items: guide.avoid)
        }
        .font(.caption)
        .padding(.vertical, Spacing.md)
    }

    private func tipGroup(_ title: LocalizedStringResource, items: [LocalizedStringResource]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text("\u{2022}")
                        .foregroundStyle(Theme.secondaryLabel)
                    Text(item)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

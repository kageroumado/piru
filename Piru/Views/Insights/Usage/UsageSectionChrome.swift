import SwiftUI

// MARK: - Index ↔ enum

/// Maps the plain indices the off-main aggregation works in back to the
/// main-actor enums the UI draws with. The aggregation can't hold these types
/// as dictionary keys (they're main-isolated under the target's default
/// isolation), so the boundary is crossed exactly here.
enum UsageAxes {
    static func category(_ index: Int) -> SubstanceCategory {
        let all = SubstanceCategory.allCases
        return all.indices.contains(index) ? all[index] : .other
    }

    static func route(_ index: Int) -> RouteOfAdministration {
        let all = RouteOfAdministration.allCases
        return all.indices.contains(index) ? all[index] : .other
    }

    static func doseLevel(_ index: Int) -> DoseLevel {
        switch index {
        case 0: .sub
        case 1: .threshold
        case 2: .light
        case 3: .common
        case 4: .strong
        default: .heavy
        }
    }

    /// Dose levels lightest → heaviest, the stacking order §4 draws bottom-up.
    static let doseLevelOrder: [Int] = [0, 1, 2, 3, 4, 5]
}

// MARK: - Substance labelling

/// Resolves a substance index to the name and color every section needs.
///
/// A value type carried by `let` so passing it into a subview doesn't widen
/// that subview's invalidation boundary — it changes only when the aggregation
/// or the user's color assignments change.
struct UsageSubstanceStyle {
    let substances: [UsageSubstanceRef]
    let colorMap: [String: Color]

    func name(_ index: Int) -> String {
        guard substances.indices.contains(index) else { return "—" }
        return substances[index].displayName
    }

    func color(_ index: Int) -> Color {
        guard substances.indices.contains(index) else { return Theme.accent }
        return SubstancePalette.color(for: substances[index].name, colorMap: colorMap)
    }

    func category(_ index: Int) -> SubstanceCategory {
        guard substances.indices.contains(index) else { return .other }
        return UsageAxes.category(substances[index].categoryIndex)
    }
}

// MARK: - Cards

/// The standard Usage section card: a headline, an optional one-line
/// explanation of what the section answers, and its content.
struct UsageSectionCard<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }
}

/// A Usage section that remembers whether it's open.
///
/// Sections 6–9 of `Specs/usage-graphs-v2.md` are secondary insights, so they
/// collapse — expanded on first visit, and the choice persists per section.
struct UsageCollapsibleCard<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    /// `@AppStorage` key suffix — one per section.
    let storageKey: String
    @ViewBuilder var content: () -> Content

    @AppStorage private var isExpanded: Bool

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        storageKey: String,
        defaultExpanded: Bool = true,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.storageKey = storageKey
        self.content = content
        _isExpanded = AppStorage(wrappedValue: defaultExpanded, "usageSection.\(storageKey)")
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
                .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryLabel)
                }
            }
        }
        .tint(Theme.secondaryLabel)
        .padding()
        .themeCard()
    }
}

// MARK: - Category filter

/// The "All + one pill per category" filter bar shared by the heatmap and the
/// co-use list.
struct UsageCategoryFilterBar: View {
    let categories: [(categoryIndex: Int, count: Int)]
    @Binding var selection: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                pill(label: Text("All"), color: Theme.accent, isSelected: selection == nil) {
                    selection = nil
                }
                ForEach(categories, id: \.categoryIndex) { item in
                    let category = UsageAxes.category(item.categoryIndex)
                    pill(
                        label: Text(category.displayName),
                        color: category.color,
                        isSelected: selection == item.categoryIndex,
                    ) {
                        selection = selection == item.categoryIndex ? nil : item.categoryIndex
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func pill(label: Text, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                label
                    .font(.caption2.weight(.medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isSelected ? color.opacity(0.25) : Color.clear)
            .foregroundStyle(.primary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? color : Color(.quaternaryLabel)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

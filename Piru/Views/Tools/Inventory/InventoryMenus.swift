import SwiftUI

// MARK: - Options menu

/// The inventory manager's single overflow menu — everything except the one
/// primary action (`+`).
///
/// Sort, grouping, filtering, and edit mode would be four toolbar buttons; at
/// that point the bar is louder than the list it controls. Files.app solves the
/// same problem the same way, and its ordering is the one followed here:
/// selection first, then how the list is arranged, then how it's narrowed.
struct InventoryOptionsMenu: View {
    @Bindable var model: InventoryListModel
    /// Every class present in the inventory — the class facet offers only these.
    let categories: [SubstanceCategory]
    /// Flipped by "Edit", which is how deletion is reached without a swipe.
    @Binding var editMode: EditMode
    /// Opens the class-arrangement sheet, which the list owns.
    let onArrangeClasses: () -> Void

    /// `true` when every present class is folded, which flips the fold-all row
    /// between Collapse All and Expand All.
    private var allCollapsed: Bool {
        !categories.isEmpty && categories.allSatisfy(model.collapsedCategories.contains)
    }

    /// Spoken state for the whole menu: what it's sorted by, and what's filtered.
    /// Both are otherwise only visible after opening it.
    private var optionsValue: Text {
        var parts = [String(localized: model.sort.displayName)]
        parts += model.filterStatuses.map { String(localized: $0.displayName) }.sorted()
        parts += model.filterCategories.map { String(localized: $0.displayName) }.sorted()
        return Text(verbatim: parts.joined(separator: ", "))
    }

    var body: some View {
        Menu {
            Section {
                // "Edit" rather than Files' "Select": this mode reveals the
                // per-row delete control (and, in Manual sort, the drag grabbers)
                // instead of starting a multi-select. It's the reachable path to
                // deleting for anyone who doesn't know about — or can't perform —
                // a swipe.
                Button {
                    editMode = .active
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }

            Section {
                Toggle(isOn: $model.isGrouped) {
                    Label("Group by Class", systemImage: "square.grid.2x2")
                }
                // Only meaningful once there are sections to fold or arrange.
                if model.isGrouped, categories.count > 1 {
                    Button {
                        model.setAllCollapsed(!allCollapsed, in: categories)
                    } label: {
                        allCollapsed
                            ? Label("Expand All", systemImage: "arrow.down.left.and.arrow.up.right")
                            : Label("Collapse All", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    Button {
                        onArrangeClasses()
                    } label: {
                        Label("Arrange Classes…", systemImage: "arrow.up.arrow.down")
                    }
                }
            }

            Section {
                Picker(selection: $model.sort) {
                    ForEach(InventorySort.allCases) { option in
                        Label {
                            Text(option.displayName)
                        } icon: {
                            Image(systemName: option.icon)
                        }
                        .tag(option)
                    }
                } label: {
                    Text("Sort By")
                }
                .pickerStyle(.inline)
            }

            Section {
                filterMenu
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
        }
        .accessibilityLabel(Text("More"))
        .accessibilityValue(optionsValue)
    }

    /// Filters live one level down, as a single "Filter" row rather than two
    /// top-level facets — a bare "Status" submenu would sit directly under the
    /// *sort* option also called "Status" and read as the same control.
    private var filterMenu: some View {
        Menu {
            Menu {
                ForEach(StockStatus.allCases) { status in
                    toggleRow(
                        isOn: model.filterStatuses.contains(status),
                        title: Text(status.displayName),
                        icon: status.icon,
                    ) { toggle(status, in: \.filterStatuses) }
                }
            } label: {
                facetLabel("Status", systemImage: "shippingbox", count: model.filterStatuses.count)
            }

            if categories.count > 1 {
                Menu {
                    ForEach(categories) { category in
                        toggleRow(
                            isOn: model.filterCategories.contains(category),
                            title: Text(category.displayName),
                            icon: category.icon,
                        ) { toggle(category, in: \.filterCategories) }
                    }
                } label: {
                    facetLabel("Class", systemImage: "square.grid.2x2", count: model.filterCategories.count)
                }
            }

            if model.hasActiveFilters {
                Section {
                    Button("Clear Filters", role: .destructive) { model.clearFilters() }
                }
            }
        } label: {
            facetLabel(
                "Filter",
                systemImage: "line.3.horizontal.decrease",
                count: model.filterStatuses.count + model.filterCategories.count,
            )
        }
    }

    /// A submenu's title with a `(count)` suffix once that facet has selections,
    /// so the collapsed level above advertises what's applied.
    private func facetLabel(_ title: LocalizedStringResource, systemImage: String, count: Int) -> some View {
        Label {
            if count > 0 {
                Text(verbatim: "\(String(localized: title)) (\(count))")
            } else {
                Text(title)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }

    /// A checkmark toggle row inside a facet submenu; the facet's own glyph
    /// stands in for the checkmark while unselected.
    private func toggleRow(
        isOn: Bool,
        title: Text,
        icon: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Label {
                title
            } icon: {
                Image(systemName: isOn ? "checkmark" : icon)
            }
        }
    }

    private func toggle<Value: Hashable>(
        _ value: Value,
        in keyPath: ReferenceWritableKeyPath<InventoryListModel, Set<Value>>,
    ) {
        if model[keyPath: keyPath].contains(value) {
            model[keyPath: keyPath].remove(value)
        } else {
            model[keyPath: keyPath].insert(value)
        }
    }
}

// MARK: - Active filter bar

/// The removable chips shown under the title while a filter is applied. With the
/// filter controls now buried in the overflow menu, this bar *is* the indicator
/// that the list is narrowed — so it stays pinned rather than scrolling away.
struct InventoryFilterBar: View {
    @Bindable var model: InventoryListModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(model.filterStatuses).sorted(by: { $0.sortIndex < $1.sortIndex })) { status in
                    chip(Text(status.displayName)) { model.filterStatuses.remove(status) }
                }
                ForEach(model.filterCategories.sorted(by: {
                    String(localized: $0.displayName) < String(localized: $1.displayName)
                })) { category in
                    chip(Text(category.displayName)) { model.filterCategories.remove(category) }
                }
                Button("Clear") { model.clearFilters() }
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: Text, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 4) {
                title
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.accent.opacity(0.16), in: Capsule())
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Remove filter"))
        .accessibilityValue(title)
    }
}

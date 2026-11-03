// Piru/Navigation/SplitNavigationView.swift for Android. SkipFuseUI provides no
// NavigationSplitView, so a regular-width window (a tablet, an unfolded foldable) lays the
// list and the opened record side by side in two stacks; a compact window is the tab's plain
// stack. The path rules are upstream's SplitPath, so a record opens beside its list exactly as
// on iOS, and the window's width class comes from Compose's window-size classes.

import SwiftUI

struct AndroidSplitNavigation<Root: View>: View {
    @Environment(\.appNavigator) private var navigator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let tab: TabID
    let root: Root

    private var split: SplitPath {
        SplitPath(navigator.path(for: tab))
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            panes(split)
        } else {
            NavigationStack(path: navigator.pathBinding(for: tab)) {
                root
                    .withAppDestinations()
            }
        }
    }

    private func panes(_ split: SplitPath) -> some View {
        columns(split)
            .confirmationDialog(
                "Discard your changes?",
                isPresented: Binding(
                    get: { navigator.pendingRecordChange?.tab == tab },
                    set: { if !$0 { navigator.resolvePendingRecordChange(discard: false) } },
                ),
                titleVisibility: .visible,
            ) {
                Button("Discard Changes", role: .destructive) {
                    navigator.resolvePendingRecordChange(discard: true)
                }
                Button("Keep Editing", role: .cancel) {
                    navigator.resolvePendingRecordChange(discard: false)
                }
            } message: {
                Text("The entry you are editing has changes that are not saved.")
            }
    }

    private func columns(_ split: SplitPath) -> some View {
        HStack(spacing: 0) {
            NavigationStack(path: Binding(
                get: { split.list },
                set: { navigator.setList($0, in: tab) },
            )) {
                root
                    .withAppDestinations()
            }
            .environment(\.opensRecordsBesideList, true)
            .environment(\.selectedRecord, split.record)
            .frame(maxWidth: split.record == nil ? .infinity : SplitPaneGeometry.minimumPaneWidth)

            if let record = split.record {
                Divider()
                NavigationStack(path: Binding(
                    get: { Array(split.detail.dropFirst()) },
                    set: { navigator.setPath(self.split.detailChanged(to: $0), in: tab) },
                )) {
                    PushRouteView(route: record)
                        .id(record)
                        .withAppDestinations()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close record", systemImage: "xmark") {
                                    navigator.closeRecord(in: tab)
                                }
                            }
                        }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

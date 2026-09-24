import SwiftData
import SwiftUI

/// What a timeline dose bubble offers beyond its tap: a long-press menu
/// (Edit, Substance Info, Delete) and, on iOS, swipe-left-to-delete — the
/// dose-level actions the entry detail's ⋯ menu holds, reachable from the
/// Journal without opening the dose.
///
/// `preview` is what the long press lifts. The bubbles of a group share one
/// `GlassEffectContainer`, and the system's default lift snapshots the whole
/// container — every bubble in the group — so the menu names its own.
extension View {
    func timelineDoseActions(
        _ item: TimelineDayLayout.CardItem,
        bubbleWidth: CGFloat,
        @ViewBuilder preview: @escaping () -> some View,
    ) -> some View {
        modifier(TimelineDoseActionsModifier(item: item, bubbleWidth: bubbleWidth, preview: preview))
    }
}

private struct TimelineDoseActionsModifier<Preview: View>: ViewModifier {
    let item: TimelineDayLayout.CardItem
    let bubbleWidth: CGFloat
    let preview: () -> Preview

    @Environment(\.appNavigator) private var navigator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.sessionEditingService) private var editing

    func body(content: Content) -> some View {
        let menued = content
            .contextMenu { menu } preview: { preview() }
        #if os(iOS)
            menued.modifier(TimelineBubbleSwipe(width: bubbleWidth, onDelete: delete))
        #else
            menued
        #endif
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            editing.pendingEditEntryID = item.id
            navigator.push(.entry(timestamp: item.timestamp, id: item.id))
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button {
            navigator.push(.substance(name: item.substance))
        } label: {
            Label("Substance Info", systemImage: "info.circle")
        }
        Divider()
        Button(role: .destructive, action: delete) {
            Label("Delete", systemImage: "trash")
        }
    }

    private func delete() {
        let id = item.id
        var descriptor = FetchDescriptor<DoseEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let entry = try? modelContext.fetch(descriptor).first else { return }
        editing.delete(entry, in: modelContext)
    }
}

#if os(iOS)
    /// Swipe a bubble left to uncover a Delete button in the space it leaves;
    /// swipe past ``fullSwipeFraction`` of its width and let go to delete
    /// outright. A tap on an uncovered bubble closes it rather than opening
    /// the dose.
    private struct TimelineBubbleSwipe: ViewModifier {
        let width: CGFloat
        let onDelete: () -> Void

        @State private var offset: CGFloat = 0
        @State private var dragStart: CGFloat?
        @State private var armed = false

        private static let revealWidth: CGFloat = 72
        private static let buttonGap: CGFloat = 6
        private static let fullSwipeFraction: CGFloat = 0.6
        /// Seconds of release velocity folded into where the swipe settles.
        private static let velocityProjection: CGFloat = 0.15

        private var fullSwipeDistance: CGFloat {
            width * Self.fullSwipeFraction
        }

        func body(content: Content) -> some View {
            content
                .overlay {
                    if offset != 0 {
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture { settle(at: 0) }
                    }
                }
                .offset(x: offset)
                .background(alignment: .trailing) { deleteButton }
                .gesture(HorizontalSwipePan(onChanged: drag, onEnded: release))
        }

        @ViewBuilder
        private var deleteButton: some View {
            let uncovered = max(0, -offset - Self.buttonGap)
            if uncovered > 0 {
                let shape = RoundedRectangle(cornerRadius: TimelineDoseBubble.cornerRadius, style: .continuous)
                Button(role: .destructive, action: commitDelete) {
                    // The icon rides as an overlay so the button's width is
                    // only ever the uncovered strip, never the glyph's.
                    shape
                        .fill(Color.red)
                        .overlay {
                            Image(systemName: "trash")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .opacity(min(1, uncovered / Self.revealWidth))
                        }
                        .frame(width: uncovered)
                        .clipShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Delete"))
            }
        }

        private func drag(_ translation: CGFloat) {
            let start = dragStart ?? offset
            dragStart = start
            offset = min(0, start + translation)
            let pastFull = -offset > fullSwipeDistance
            if pastFull != armed {
                armed = pastFull
                PlatformHaptics.impact()
            }
        }

        private func release(_ translation: CGFloat, velocity: CGFloat) {
            let start = dragStart ?? offset
            dragStart = nil
            armed = false
            let final = start + translation
            if -final > fullSwipeDistance {
                commitDelete()
                return
            }
            let projected = final + velocity * Self.velocityProjection
            settle(at: -projected > Self.revealWidth / 2 ? -(Self.revealWidth + Self.buttonGap) : 0)
        }

        private func settle(at target: CGFloat) {
            withAnimation(.snappy(duration: 0.25)) { offset = target }
        }

        private func commitDelete() {
            withAnimation(.snappy(duration: 0.2)) { offset = -(width + Self.buttonGap) }
            onDelete()
        }
    }
#endif

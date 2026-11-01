import SwiftData
import SwiftUI

/// The long-press menu of a timeline dose bubble (Edit, Substance Info,
/// Delete): the dose-level actions the entry detail's ⋯ menu holds, reachable
/// from the Journal without opening the dose. The bubble presents it as a
/// `Menu` with the tap as its primary action. Never as `.contextMenu`: in the
/// Journal's Timeline `List`, a row's context menu belongs to its cell, so
/// every bubble in a day would open the day's first dose and lift the whole row.
struct TimelineDoseMenu: View {
    let item: TimelineDayLayout.CardItem

    @Environment(\.appNavigator) private var navigator
    @Environment(\.opensRecordsBesideList) private var opensRecordsBesideList
    @Environment(\.modelContext) private var modelContext
    @Environment(\.sessionEditingService) private var editing

    var body: some View {
        Button {
            editing.pendingEditEntryID = item.id
            navigator.openRecord(.entry(timestamp: item.timestamp, id: item.id), besideList: opensRecordsBesideList)
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button {
            navigator.openRecord(.substance(name: item.substance), besideList: opensRecordsBesideList)
        } label: {
            Label("Substance Info", systemImage: "info.circle")
        }
        Divider()
        Button(role: .destructive) {
            TimelineDoseDeletion.delete(item, in: modelContext, editing: editing)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

enum TimelineDoseDeletion {
    static func delete(_ item: TimelineDayLayout.CardItem, in modelContext: ModelContext, editing: SessionEditingService) {
        let id = item.id
        var descriptor = FetchDescriptor<DoseEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let entry = try? modelContext.fetch(descriptor).first else { return }
        editing.delete(entry, in: modelContext)
    }
}

extension View {
    /// On iOS, swipe-left-to-delete on a timeline dose bubble.
    @ViewBuilder
    func timelineDoseSwipe(_ item: TimelineDayLayout.CardItem, bubbleWidth: CGFloat) -> some View {
        #if os(iOS)
            modifier(TimelineDoseSwipeModifier(item: item, bubbleWidth: bubbleWidth))
        #else
            self
        #endif
    }
}

#if os(iOS)
    private struct TimelineDoseSwipeModifier: ViewModifier {
        let item: TimelineDayLayout.CardItem
        let bubbleWidth: CGFloat

        @Environment(\.modelContext) private var modelContext
        @Environment(\.sessionEditingService) private var editing

        func body(content: Content) -> some View {
            content.modifier(TimelineBubbleSwipe(width: bubbleWidth) {
                TimelineDoseDeletion.delete(item, in: modelContext, editing: editing)
            })
        }
    }
#endif

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

import SwiftData
import SwiftUI

/// The journal's real vertical timeline, drawn in any skin, for ``SkinPreviewCard``.
///
/// One fixed day of made-up doses goes through ``TimelineStripBuilder`` — the
/// builder the Journal uses — so the preview is the app's own timeline rather
/// than a drawing of one, and every card shows the same day. Each skin's copy is
/// then rendered once, offscreen, at the phone's own width and pixel scale, and
/// the card scales that picture down over its live backdrop.
///
/// It has to be a picture. The timeline's views read the skin the app is
/// wearing through `Theme`, so a row of live timelines would all wear the same
/// one; ``SkinStore/rendering(as:_:)`` scopes a skin to one synchronous render,
/// which is exactly what an `ImageRenderer` is.
@Observable
@MainActor
final class SkinPreviewTimeline {
    static let shared = SkinPreviewTimeline()

    /// The screen the picture is drawn at, in points: a phone's width, and the
    /// height the card's proportions give it.
    static let screenSize = CGSize(width: 390, height: 674)

    /// The fixed day, laid out. Empty until ``prepare()`` has run.
    private(set) var days: [TimelineDayLayout] = []

    @ObservationIgnored private var snapshots: [SnapshotKey: Image] = [:]
    @ObservationIgnored private var preparation: Task<Void, Never>?

    private struct SnapshotKey: Hashable {
        let skin: Skin
        let dark: Bool
    }

    /// The made-up day, as offsets into yesterday so no dose is still active and
    /// the layout never depends on the time the picker is opened.
    private struct Dose {
        let substance: String
        let amount: Double
        let hour: Int
        let minute: Int
    }

    /// An evening, because the strip runs newest-first and the card shows its
    /// top seven hours or so: every dose here lands inside the frame.
    private static let doses: [Dose] = [
        Dose(substance: "Caffeine", amount: 100, hour: 16, minute: 30),
        Dose(substance: "L-Theanine", amount: 200, hour: 16, minute: 45),
        Dose(substance: "Caffeine", amount: 80, hour: 19, minute: 0),
        Dose(substance: "Magnesium", amount: 300, hour: 20, minute: 30),
        Dose(substance: "Melatonin", amount: 1, hour: 22, minute: 15),
    ]

    /// Lays the fixed day out, once. The entries live in a throwaway in-memory
    /// store that is gone when this returns; the layouts are plain values.
    /// Every card asks; they all wait on the one build.
    func prepare() async {
        if preparation == nil {
            preparation = Task(name: "Skin preview timeline") { await self.build() }
        }
        await preparation?.value
    }

    private func build() async {
        await SubstanceStore.shared.ensureAllLoaded()
        guard let container = try? ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        ) else { return }
        let context = ModelContext(container)
        let calendar = Calendar.current
        let yesterday = calendar.startOfDay(for: .now).addingTimeInterval(-86400)
        let entries = Self.doses.compactMap { dose -> DoseEntry? in
            guard let timestamp = calendar.date(bySettingHour: dose.hour, minute: dose.minute, second: 0, of: yesterday) else { return nil }
            let entry = DoseEntry(substance: dose.substance, amount: dose.amount, timestamp: timestamp)
            context.insert(entry)
            return entry
        }
        guard var builder = TimelineStripBuilder(
            entries: entries,
            colors: [],
            colorMap: [:],
            zoom: 1,
            compressGaps: true,
            style: TimelineDayLayout.Style(showsAxis: true, bubbleStyle: .full, pkMode: false),
        ) else { return }
        // Only the day that holds the doses: today's slice is an empty live
        // edge, and it would push the day worth looking at out of the card.
        days = (0 ..< builder.sliceCount)
            .map { builder.layout(sliceAt: $0) }
            .filter { !$0.cardGroups.isEmpty }
    }

    /// The timeline in `skin`, rendered on first request and kept.
    func snapshot(for skin: Skin, dark: Bool, scale: CGFloat) -> Image? {
        let key = SnapshotKey(skin: skin, dark: dark)
        if let cached = snapshots[key] { return cached }
        guard !days.isEmpty else { return nil }
        let content = SkinPreviewScreen(days: days, skin: skin)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.rendersTimelineFlat, true)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(Self.screenSize)
        guard let rendered = SkinStore.shared.rendering(as: skin, { renderer.cgImage }) else { return nil }
        let image = Image(decorative: rendered, scale: scale)
        snapshots[key] = image
        return image
    }
}

/// The Journal's title and the fixed day under it, on a clear ground so the
/// card's backdrop shows through. Photographed for every skin, and shown live
/// by the card whose skin the app is wearing.
struct SkinPreviewScreen: View {
    let days: [TimelineDayLayout]
    let skin: Skin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Journal")
                .font(.piru(.largeTitle, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 64)
                .padding(.bottom, Spacing.xl)
            ForEach(days) { day in
                TimelineDayContent(day: day)
            }
        }
        .frame(
            width: SkinPreviewTimeline.screenSize.width,
            height: SkinPreviewTimeline.screenSize.height,
            alignment: .top,
        )
        .clipped()
        // What `SkinnedRoot` gives every real screen.
        .tint(skin.accent)
        .fontDesign(skin.fontDesign)
    }
}

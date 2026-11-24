import SwiftData
import SwiftUI

/// A picture of the Journal in any skin, for ``SkinPreviewCard``.
///
/// One fixed day of made-up doses goes through ``TimelineStripBuilder`` — the
/// builder the Journal uses — so the preview is the app's own timeline rather
/// than a drawing of one, and every card shows the same day. Each skin's card
/// is then rendered once, offscreen: its backdrop held on one frame, and the
/// timeline over it.
///
/// It has to be a picture. The timeline's views read the skin the app is
/// wearing through `Theme`, so a row of live timelines would all wear the same
/// one; ``SkinStore/rendering(as:_:)`` scopes a skin to one synchronous render,
/// which is exactly what an `ImageRenderer` is. And a grid of eighteen cards
/// has to scroll: one small image each, where a live backdrop is a canvas the
/// size of a phone.
@Observable
@MainActor
final class SkinPreviewTimeline {
    static let shared = SkinPreviewTimeline()

    /// The screen the picture is drawn at, in points: a phone's width, and the
    /// height the card's proportions give it.
    static let screenSize = CGSize(width: 390, height: 674)

    /// The fixed day, laid out. Empty until ``prepare(in:)`` has run.
    private(set) var days: [TimelineDayLayout] = []

    /// The words the pictures are drawn in: the language every string and
    /// clock time is looked up in, and whether substance titles are the
    /// English ones. The day is laid out, and every picture taken, in one
    /// wording; a different one lays the day out again.
    nonisolated struct Wording: Hashable, Sendable {
        let localization: String
        let englishNames: Bool

        /// The wording the app is in now.
        static var current: Wording {
            Wording(localization: AppLanguageRuntime.localization, englishNames: LocalizedSubstanceName.usesEnglishNames)
        }
    }

    @ObservationIgnored private var snapshots: [SnapshotKey: Image] = [:]
    @ObservationIgnored private var preparation: Task<Void, Never>?
    /// The wording ``days`` and ``snapshots`` are in, once a preparation started.
    @ObservationIgnored private(set) var preparedWording: Wording?
    /// The newest render in the queue; the next one waits on it.
    @ObservationIgnored private var lastRender: Task<Void, Never>?

    /// How many pictures are kept.
    var snapshotCount: Int {
        snapshots.count
    }

    private struct SnapshotKey: Hashable {
        let skin: Skin
        let dark: Bool
        let wording: Wording
    }

    /// The made-up day, as offsets into yesterday so no dose is still active and
    /// the layout never depends on the time the picker is opened.
    private struct Dose {
        let substance: String
        let amount: Double
        let hour: Int
        let minute: Int
    }

    /// An evening, because the strip runs newest-first from the end of the last
    /// dose's effect, hours after the dose itself. At ``zoom`` the card holds
    /// about ten hours, which takes in that tail and every dose here.
    private static let doses: [Dose] = [
        Dose(substance: "Caffeine", amount: 100, hour: 18, minute: 0),
        Dose(substance: "L-Theanine", amount: 200, hour: 18, minute: 15),
        Dose(substance: "Caffeine", amount: 80, hour: 19, minute: 30),
        Dose(substance: "Magnesium", amount: 300, hour: 20, minute: 45),
        Dose(substance: "Melatonin", amount: 1, hour: 22, minute: 15),
    ]

    /// The strip's time scale: a miniature has to show a whole evening.
    private static let zoom = 0.6

    /// The picture's size against the screen it is a picture of. No card is
    /// drawn wider than this share of a phone's width, and a full-size picture
    /// of every skin would hold four times the memory.
    private static let pictureScale: CGFloat = 0.5
    /// One frame, left between two renders.
    private static let renderSpacing: Duration = .milliseconds(16)

    /// Lays the fixed day out, once per wording. The entries live in a
    /// throwaway in-memory store that is gone when this returns; the layouts
    /// are plain values. Every card asks; they all wait on the one build. A
    /// new wording drops the pictures taken in the old one.
    func prepare(in wording: Wording = .current) async {
        if preparation == nil || preparedWording != wording {
            preparedWording = wording
            snapshots.removeAll()
            preparation = Task(name: "Skin preview timeline") {
                let built = await self.build()
                // A later wording's build owns `days` once it has started.
                if self.preparedWording == wording {
                    self.days = built
                }
            }
        }
        await preparation?.value
    }

    private func build() async -> [TimelineDayLayout] {
        await SubstanceStore.shared.ensureAllLoaded()
        guard let container = try? ModelContainer(
            for: Schema(PiruSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none),
        ) else { return [] }
        let context = ModelContext(container)
        let calendar = Calendar.current
        // The journal day before the current one, which is still running at 02:00.
        let today = calendar.journalDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86_400)
        let entries = Self.doses.compactMap { dose -> DoseEntry? in
            guard let timestamp = calendar.date(bySettingHour: dose.hour, minute: dose.minute, second: 0, of: yesterday) else { return nil }
            let entry = DoseEntry(substance: dose.substance, amount: dose.amount, timestamp: timestamp)
            context.insert(entry)
            return entry
        }
        // Each substance's class color, named here: the app publishes its
        // catalog of them at launch, and a picker opened in the first second
        // would otherwise draw every curve in the neutral gray.
        var colorMap: [String: Color] = [:]
        for dose in Self.doses {
            guard let substance = SubstanceLibrary.lookup(dose.substance) else { continue }
            colorMap[dose.substance.lowercased()] = SubstanceColorGenerator.color(for: substance).displayP3.color
        }
        guard var builder = TimelineStripBuilder(
            entries: entries,
            colors: [],
            colorMap: colorMap,
            zoom: Self.zoom,
            compressGaps: true,
            style: TimelineDayLayout.Style(showsAxis: true, bubbleStyle: .full, pkMode: false),
        ) else { return [] }
        // Only the day that holds the doses: today's slice is an empty live
        // edge, and it would push the day worth looking at out of the card.
        return (0 ..< builder.sliceCount)
            .map { builder.layout(sliceAt: $0) }
            .filter { !$0.cardGroups.isEmpty }
    }

    /// The card in `skin`, rendered on first request and kept. `nil` when the
    /// render produced nothing; asking again tries again.
    ///
    /// Renders run one at a time with a frame between them, so a screen that
    /// shows many cards at once fills them in over a few frames while it stays
    /// under the finger. A caller cancelled while its render waits in the
    /// queue gets `nil`, and its render never runs.
    func snapshot(for skin: Skin, dark: Bool, scale: CGFloat, in wording: Wording = .current) async -> Image? {
        let key = SnapshotKey(skin: skin, dark: dark, wording: wording)
        if let cached = snapshots[key] { return cached }
        await prepare(in: wording)
        guard !Task.isCancelled else { return nil }
        let previous = lastRender
        let render = Task(name: "Skin preview render") { () -> Image? in
            await previous?.value
            if let cached = self.snapshots[key] { return cached }
            try? await Task.sleep(for: Self.renderSpacing)
            guard !Task.isCancelled else { return nil }
            return self.render(key, scale: scale)
        }
        lastRender = Task(name: "Skin preview queue") { _ = await render.value }
        return await withTaskCancellationHandler {
            await render.value
        } onCancel: {
            render.cancel()
        }
    }

    /// Renders every skin's card ahead of the screen that will show them all,
    /// until the screen goes away.
    func warm(dark: Bool, scale: CGFloat) async {
        for skin in Skin.available {
            guard !Task.isCancelled else { return }
            _ = await snapshot(for: skin, dark: dark, scale: scale)
        }
    }

    private func render(_ key: SnapshotKey, scale: CGFloat) -> Image? {
        // The day laid out in another wording would put that wording's words
        // in this picture.
        guard !days.isEmpty, preparedWording == key.wording else { return nil }
        let content = ZStack {
            SkinBackdrop(skin: key.skin, animates: false)
            SkinPreviewScreen(days: days, skin: key.skin)
        }
        .frame(width: Self.screenSize.width, height: Self.screenSize.height)
        .environment(\.colorScheme, key.dark ? .dark : .light)
        .environment(\.locale, AppLanguageRuntime.locale(for: key.wording.localization, base: .current))
        .environment(\.rendersTimelineFlat, true)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale * Self.pictureScale
        renderer.proposedSize = ProposedViewSize(Self.screenSize)
        guard let rendered = SkinStore.shared.rendering(as: key.skin, { renderer.cgImage }) else { return nil }
        let image = Image(decorative: rendered, scale: renderer.scale)
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

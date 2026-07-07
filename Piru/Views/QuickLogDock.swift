import Speech
import SwiftUI

// MARK: - Metrics

/// Geometry shared between the dock sheet and the quick-log cover behind it.
enum QuickLogDockMetrics {
    /// The pinned search field's height — one size in every dock state.
    static let fieldHeight: CGFloat = 48
    /// How far the compact search bar floats above the physical screen bottom.
    static let bareFloat: CGFloat = 12
    /// Vertical chrome around the pinned search field (16 top clears the
    /// grabber, 6 below) — part of every detent's height budget.
    static let searchBlockHeight: CGFloat = fieldHeight + 16 + 6
    /// The rest detent: the floating search bar. Detent heights are measured
    /// from the screen bottom (they include the home-indicator region), so
    /// this is bar + float.
    static let peekHeight: CGFloat = searchBlockHeight + bareFloat
    static let peekDetent = PresentationDetent.height(peekHeight)
    /// Detents while nothing is staged: the floating bar, browse height, and
    /// full height for search. `.medium` must stay a member of *every* detent
    /// set — `presentationBackgroundInteraction(.enabled(upThrough: .medium))`
    /// resolves against the set, and without the member the system falls back
    /// to a fully modal (dimmed, touch-blocking) presentation. The
    /// fit-to-content compact detent joins once the tray holds doses (see
    /// ``QuickLogDock/refreshDetents()``).
    static let emptyDetents: Set<PresentationDetent> = [peekDetent, .medium, .large]
}

// MARK: - Dock Sheet

/// The staging dock — a native detented sheet presented over the quick-log
/// cover (the Apple Maps model: browse list behind, resizable dock on top).
///
/// One search bar is pinned at the top in every detent so it keeps a single
/// view identity as the sheet resizes. Beneath it the content composes rather
/// than swaps: search results (or browse suggestions) appear above the staged
/// list, which never disappears while searching; the shared chips + Log
/// button stay pinned to the sheet's bottom edge whenever something is
/// staged. The sheet is never dismissible (it's the staging basket, not a
/// throwaway sheet); it collapses to its smallest detent instead.
///
/// Detents are dynamic: with an empty tray the dock rests at the bare search
/// pill; once doses are staged the smallest detent becomes a *fit-to-content*
/// compact height (collapsed rows + Log button, measured live). Dragging down
/// to compact collapses every inline editor; dragging back up restores them.
///
/// State ownership: the tray, content caches, and search text live on
/// `QuickLogView` (browse-list taps stage into the same tray). The dock owns
/// only what's local to its surface — keyboard focus, dictation, and the
/// detent transitions.
struct QuickLogDock: View {
    var tray: DoseTrayModel
    var content: QuickLogContentModel
    /// Height of the quick-log cover — caps the compact detent so a tall
    /// stack never pushes it past medium.
    var containerHeight: CGFloat
    @Binding var searchText: String
    @Binding var searchActive: Bool
    @Binding var detent: PresentationDetent
    @Binding var detents: Set<PresentationDetent>

    let onStageRecent: (SubstanceCard) -> Void
    let onOpenSubstance: (Substance) -> Void
    let onCreateCustom: () -> Void
    let onCommit: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var customSubstanceStore = CustomSubstanceStore.shared
    @State private var dictation = DockDictation()

    /// The bare (Maps collapsed-pill) face: nothing but the floating search
    /// pill. Driven by the *live* sheet height, not the settled detent, so the
    /// content morphs pill → surface continuously while the user drags.
    private var isBare: Bool {
        sheetHeight < QuickLogDockMetrics.peekHeight + 40
    }

    /// Live height of the sheet's content area, reported by geometry — the
    /// detent `selection` only updates when a drag settles.
    @State private var sheetHeight: CGFloat = 0

    // MARK: Compact-detent measurements

    /// Rendered height of the pinned commit bar (chips + Log button + any
    /// open panel).
    @State private var commitBarHeight: CGFloat = 0
    /// The current fit-to-content compact detent, kept alongside ``detents``
    /// so detent-change handlers can recognise it by value.
    @State private var compactDetent: PresentationDetent?
    /// The height the current ``compactDetent`` was minted at — refreshes are
    /// skipped for sub-6pt drift so transient re-measures (the commit bar
    /// animating a panel open, geometry settling) don't re-mint the detent
    /// mid-gesture.
    @State private var compactValue: CGFloat = 0

    // MARK: Browse suggestions

    /// The effect-family pills shown in the suggestions state (resolved once —
    /// the taxonomy is static over a session).
    @State private var families: [LibraryFamily] = []
    @State private var selectedFamilyID: String?
    /// Top-by-popularity substances of the selected family.
    @State private var browseResults: [Substance] = []

    var body: some View {
        VStack(spacing: 0) {
            // The search bar is identical in every dock state — same field,
            // same insets. In the compact pill it sits above the vertical
            // centre (grabber over it, tighter below); that asymmetry is
            // deliberate, matching the full faces.
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    middleContent
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            // Maps behaviour: dragging up inside the dock resizes it first;
            // content scrolls only at the tallest detent. The greedy scroll
            // area is also what pins the commit bar to the sheet's bottom.
            .scrollDisabled(detent != .large)
            .scrollDismissesKeyboard(.interactively)

            if !tray.isEmpty, !isBare {
                TrayCommitBar(
                    model: tray,
                    tagSuggestions: content.cachedTagSuggestions,
                    recentLocations: content.cachedRecentLocations,
                    onCommit: onCommit,
                )
                .padding(.horizontal, 16)
                // Intrinsic height always: when a drag squeezes the sheet
                // below the compact detent, the bar must clip rather than
                // compress — a compressed measurement re-minted the compact
                // detent mid-gesture and snapped the sheet to the wrong one.
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { newValue in
                    guard abs(newValue - commitBarHeight) > 0.5 else { return }
                    commitBarHeight = newValue
                }
            }
        }
        // Bare: intrinsic height (just the search bar), pinned to the sheet's
        // top edge so the fixed ``bareFloat`` gap is what remains below.
        // Full: fill the sheet. The system sheet's glass platter is the
        // dock's surface in every state — we draw no chrome of our own.
        .frame(maxWidth: .infinity, maxHeight: isBare ? nil : .infinity, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        // At peek the sheet is shorter than the home-indicator inset would
        // allow — position the pill manually instead. Full faces keep the
        // regular safe-area behaviour (only their *glass* bleeds below).
        .ignoresSafeArea(.container, edges: isBare ? .bottom : [])
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { newValue in
            sheetHeight = newValue
        }
        .animation(.snappy, value: isBare)
        // Presentation configuration (detents, clear background, background
        // interaction) is applied by `QuickLogView` at the sheet closure's
        // root — attached in here it competes with the nested `.sheet`/
        // `.fullScreenCover` wrappers layered on top of this view.
        .onChange(of: searchFocused) {
            if searchFocused {
                withAnimation(.snappy) {
                    searchActive = true
                    detent = .large
                }
            } else if searchText.isEmpty, searchActive, !dictation.isListening {
                withAnimation(.snappy) { searchActive = false }
            }
        }
        // External exits (staging a result, the browse list's cancel) flip
        // `searchActive` off — release focus and settle onto the right detent.
        .onChange(of: searchActive) {
            guard !searchActive else { return }
            searchFocused = false
            dictation.stop()
            selectedFamilyID = nil
            browseResults = []
            withAnimation(.snappy) { settleDetent() }
        }
        .onChange(of: detent) { oldValue, newValue in
            detentChanged(from: oldValue, to: newValue)
        }
        // A first staged dose (from the browse list behind, at peek) grows the
        // dock just enough to show the collapsed tray + Log button.
        .onChange(of: tray.stageTick) {
            guard !searchActive, detent == QuickLogDockMetrics.peekDetent else { return }
            withAnimation(.snappy) {
                refreshDetents()
                if let compactDetent { detent = compactDetent }
            }
        }
        // A draft staged for editing (search result, routine deep link) needs
        // the editor visible — compact can't show it.
        .onChange(of: tray.expandedItemIDs) {
            guard !tray.expandedItemIDs.isEmpty,
                  detent == QuickLogDockMetrics.peekDetent || detent == compactDetent
            else { return }
            withAnimation(.snappy) { detent = .medium }
        }
        .onChange(of: tray.isEmpty) {
            withAnimation(.snappy) {
                refreshDetents()
                if tray.isEmpty, !searchActive { detent = QuickLogDockMetrics.peekDetent }
            }
        }
        // Keep the fit-to-content detent tracking its content: row heights,
        // the commit bar (panels opening), and staging changes all funnel
        // into this one value.
        .onChange(of: compactHeightValue) {
            guard !tray.isEmpty, abs(compactHeightValue - compactValue) >= 6 else { return }
            withAnimation(.snappy) { refreshDetents() }
        }
        .onChange(of: dictation.transcript) {
            guard dictation.isListening || !dictation.transcript.isEmpty else { return }
            searchText = dictation.transcript
        }
        // A routine prestaged before the sheet mounted (notification deep
        // link) should land already showing the tray.
        .onAppear {
            families = LibraryFamily.browsable
            if !tray.isEmpty {
                refreshDetents()
                detent = tray.expandedItemIDs.isEmpty ? (compactDetent ?? .medium) : .medium
            }
        }
    }

    // MARK: Detents

    /// One collapsed row's height, derived from the type metrics `TrayRow`
    /// renders with (body title + subheadline detail + 2pt spacing + 12pt
    /// vertical padding each side). Computed, not measured: live geometry
    /// reports animated in-between frames during expand/collapse, which
    /// churned the fit-to-content detent mid-gesture.
    private var collapsedRowHeight: CGFloat {
        let title = UIFont.preferredFont(forTextStyle: .body).lineHeight
        let subtitle = UIFont.preferredFont(forTextStyle: .subheadline).lineHeight
        return (title + subtitle + 2 + 24).rounded(.up)
    }

    /// Height of the staged card with every row collapsed.
    private var estimatedStagedCardHeight: CGFloat {
        guard !tray.isEmpty else { return 0 }
        let rows = collapsedRowHeight * CGFloat(tray.staged.count)
        let dividers = CGFloat(max(0, tray.staged.count - 1)) * (1.0 / 3.0)
        return rows + dividers
    }

    /// The fit-to-content compact height: search block + collapsed staged
    /// card + commit bar, capped below medium so a tall stack degrades
    /// gracefully. `.height` detents measure *above* the home-indicator
    /// inset (the system adds it below), so the inset is not budgeted here.
    private var compactHeightValue: CGFloat {
        // Scroll-content vertical padding around the staged card (8 top + 12 bottom).
        let contentPadding: CGFloat = 20
        // Chips row (12 + 40) + Log button (14 + 48) until the bar has been
        // measured — staging at peek mints the compact detent before the bar
        // exists, and minting it at a throwaway height churned the sheet's
        // detent mapping right as it grew.
        let bar = commitBarHeight > 0 ? commitBarHeight : 114
        var raw = QuickLogDockMetrics.searchBlockHeight + contentPadding
        raw += estimatedStagedCardHeight
        raw += bar
        let cap: CGFloat = containerHeight > 0 ? containerHeight * 0.5 - 40 : 420
        return min(raw, cap).rounded()
    }

    /// Swap the detent set for the tray's current shape, keeping the
    /// selection valid (and pinned to compact while it's the selection).
    private func refreshDetents() {
        if tray.isEmpty {
            compactDetent = nil
            compactValue = 0
            detents = QuickLogDockMetrics.emptyDetents
            if !detents.contains(detent) {
                detent = searchActive ? .large : QuickLogDockMetrics.peekDetent
            }
        } else {
            let wasCompact = compactDetent != nil && detent == compactDetent
            let newValue = compactHeightValue
            let newCompact = PresentationDetent.height(newValue)
            compactDetent = newCompact
            compactValue = newValue
            detents = [newCompact, .medium, .large]
            if wasCompact || !detents.contains(detent) {
                detent = newCompact
            }
        }
    }

    /// Detent-selection side effects: leaving `.large` cancels search;
    /// arriving at compact collapses every editor; growing out of compact
    /// restores them.
    private func detentChanged(from oldValue: PresentationDetent, to newValue: PresentationDetent) {
        // Dragging the dock down leaves search — Maps behaviour.
        if newValue != .large, searchActive {
            searchFocused = false
            withAnimation(.snappy) {
                searchActive = false
                searchText = ""
            }
        }
        guard let compactDetent else { return }
        // The expansion side effects run a turn later: mutating the sheet's
        // content inside the same transaction as the detent change cancels
        // the sheet's settle animation — the selection lands on the new
        // detent while the sheet visually springs back to the old one.
        if newValue == compactDetent, oldValue != compactDetent {
            Task { @MainActor in
                // The compact detent fits *collapsed* rows only.
                withAnimation(.snappy) {
                    tray.expandedItemIDs.removeAll()
                    tray.sharedDetailsExpanded = false
                }
            }
        } else if oldValue == compactDetent,
                  newValue == .medium || newValue == .large,
                  tray.expandedItemIDs.isEmpty {
            Task { @MainActor in
                // Growing the dock re-opens every staged editor.
                withAnimation(.snappy) {
                    tray.expandedItemIDs = Set(tray.staged.map(\.id))
                }
            }
        }
    }

    private func settleDetent() {
        if tray.isEmpty {
            detent = QuickLogDockMetrics.peekDetent
        } else {
            refreshDetents()
            detent = tray.expandedItemIDs.isEmpty ? (compactDetent ?? .medium) : .medium
        }
    }

    // MARK: Search bar

    /// The single pinned field — present in every detent, so SwiftUI animates
    /// it in place as the sheet resizes and the content morphs beneath it.
    /// Trailing affordances follow the system search field: a microphone
    /// (dictation) while empty, the clear button once text exists; a
    /// full-size glass cancel appears beside the field while searching.
    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.secondaryLabel)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($searchFocused)
                    .submitLabel(.search)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        dictation.stop()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                } else {
                    // Device-only: the simulator's CoreAudio bridge aborts
                    // intermittently on mic access (AURemoteIO RPC timeout) —
                    // Apple's own speech samples are marked device-only.
                    #if !targetEnvironment(simulator)
                        micButton
                    #endif
                }
            }
            .padding(.horizontal, 14)
            .frame(height: QuickLogDockMetrics.fieldHeight)
            .background(Color(.secondarySystemFill), in: Capsule())

            if searchActive {
                Button {
                    cancelSearch()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("Cancel search")
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: searchActive)
        .animation(.snappy, value: searchText.isEmpty)
    }

    /// In-field dictation toggle, mirroring the system search field's
    /// trailing microphone. Listening state pulses the filled glyph.
    private var micButton: some View {
        Button {
            if dictation.isListening {
                dictation.stop()
            } else {
                searchActive = true
                withAnimation(.snappy) { detent = .large }
                dictation.start()
            }
        } label: {
            Image(systemName: dictation.isListening ? "microphone.fill" : "microphone")
                .foregroundStyle(dictation.isListening ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.secondaryLabel))
                .symbolEffect(.pulse, options: .repeating, isActive: dictation.isListening)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Start dictation")
    }

    private func cancelSearch() {
        searchFocused = false
        dictation.stop()
        withAnimation(.snappy) {
            searchActive = false
            searchText = ""
        }
    }

    // MARK: Content

    @ViewBuilder
    private var middleContent: some View {
        if !isBare {
            if searchActive {
                if CrisisKeywords.matches(searchText) {
                    QuickLogHelpBanner()
                } else if searchText.isEmpty {
                    suggestions
                } else {
                    groupedCard {
                        QuickLogSearchResults(
                            results: results,
                            onStageRecent: onStageRecent,
                            onOpenSubstance: onOpenSubstance,
                            onCreateCustom: {
                                // Release focus before presenting — restoring
                                // focus mid-transition on dismiss caused the
                                // SheetBridge exclusivity crash (builds 13/14).
                                searchFocused = false
                                onCreateCustom()
                            },
                        )
                    }
                }
            } else if tray.isEmpty {
                // Dragged tall with nothing staged: browse suggestions, not a
                // page of nothing.
                suggestions
            }

            if !tray.isEmpty {
                // The staged basket never disappears — search results render
                // above it, so staging more is not a context switch.
                TrayStagedListCard(model: tray)
            }
        }
    }

    /// The pre-typing search surface: effect-family pills over one-tap
    /// suggestion rows (a selected family's most known substances, or the
    /// user's recents).
    @ViewBuilder
    private var suggestions: some View {
        if !families.isEmpty {
            familyPills
        }
        if let family = families.first(where: { $0.id == selectedFamilyID }) {
            groupedCard {
                QuickLogSearchResults(
                    results: browseResults.map { .library($0) },
                    onStageRecent: onStageRecent,
                    onOpenSubstance: onOpenSubstance,
                    onCreateCustom: nil,
                )
            }
            .id(family.id)
        } else if !content.cachedCards.isEmpty {
            groupedCard {
                QuickLogSearchResults(
                    results: content.cachedCards.prefix(6).map { .recent($0) },
                    onStageRecent: onStageRecent,
                    onOpenSubstance: onOpenSubstance,
                    onCreateCustom: nil,
                )
            }
        }
    }

    /// Horizontally scrolling effect-family filter pills (Library taxonomy).
    private var familyPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(families) { family in
                    familyPill(family)
                }
            }
            // Bleed to the sheet edges so the row scrolls edge-to-edge while
            // resting pills align with the cards.
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    private func familyPill(_ family: LibraryFamily) -> some View {
        let selected = selectedFamilyID == family.id
        return Button {
            withAnimation(.snappy) {
                if selected {
                    selectedFamilyID = nil
                    browseResults = []
                } else {
                    selectedFamilyID = family.id
                    browseResults = Self.substances(for: family)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: family.icon)
                    .imageScale(.small)
                Text(family.title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                selected ? AnyShapeStyle(family.color) : AnyShapeStyle(family.color.opacity(0.15)),
                in: Capsule(),
            )
            .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(family.color))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// The most recognisable substances of one family, by curated popularity —
    /// umbrellas union their sub-classes.
    private static func substances(for family: LibraryFamily) -> [Substance] {
        let list: [Substance] = switch family.source {
        case let .category(category): SubstanceLibrary.substances(in: category)
        case let .tag(tag): SubstanceLibrary.substances(taggedWith: tag)
        case nil: family.subclasses.flatMap { SubstanceLibrary.substances(in: $0.category) }
        }
        return Array(
            list
                .sorted {
                    $0.popularity != $1.popularity
                        ? $0.popularity > $1.popularity
                        : $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
                .prefix(20),
        )
    }

    /// Inset-grouped card chrome shared by the results, suggestions, and
    /// staged surfaces — the dock's one visual container.
    private func groupedCard(@ViewBuilder content: () -> some View) -> some View {
        content()
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: DoseTrayMetrics.cardCornerRadius, style: .continuous),
            )
    }

    // MARK: Search results

    /// The ranked hits shown beneath the field (recent → library → custom).
    private var results: [QuickLogSearchResult] {
        let query = searchText.lowercased()
        guard !query.isEmpty else { return [] }
        var results: [QuickLogSearchResult] = content.cachedCards
            .filter { $0.id.contains(query) }
            .prefix(2)
            .map { .recent($0) }
        results += content.cachedLibraryResults.prefix(3).map { .library($0) }
        results += filteredCustomSubstances.prefix(1).map { .custom($0) }
        return Array(results.prefix(4))
    }

    private var filteredCustomSubstances: [Substance] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        let libraryNames = Set(content.cachedLibraryResults.map { $0.name.lowercased() })
        return customSubstanceStore.all
            .filter { custom in
                let nameLower = custom.name.lowercased()
                let displayLower = custom.displayName?.lowercased() ?? ""
                // Match the canonical name OR the personal display name, so a
                // relabelled substance is findable by the name the user gave it.
                let matches = nameLower.contains(query) || (!displayLower.isEmpty && displayLower.contains(query))
                return matches
                    && !content.cachedHistoryNames.contains(nameLower)
                    && !libraryNames.contains(nameLower)
            }
            // Resolve through the library so an override of a shipped substance
            // carries its full dose/duration data (labelled with the personal
            // name); a net-new custom falls back to its own asSubstance.
            .compactMap { SubstanceLibrary.timelineLookup($0.name) ?? $0.asSubstance }
    }
}

// MARK: - Dictation

/// Streams live speech into the dock's search field — the system search
/// field's microphone affordance, reproduced with the iOS 26 Speech
/// framework's `SpeechAnalyzer` + `DictationTranscriber`.
///
/// **Fully on-device by design.** The old `SFSpeechRecognizer` path required
/// a speech-recognition authorization whose system prompt warns that audio
/// is sent to Apple's servers — unacceptable for a dose tracker's search
/// terms. `DictationTranscriber` uses the locally installed keyboard-
/// dictation models (via `AssetInventory`): no server round-trip, no
/// speech-recognition permission — only the microphone permission.
@Observable
@MainActor
final class DockDictation {
    private(set) var isListening = false
    private(set) var transcript = ""

    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    /// Generation token: tearing down an old session must never clear state
    /// that a newer session has since taken over.
    private var generation = 0

    func start() {
        guard !isListening else { return }
        transcript = ""
        isListening = true
        let startedGeneration = generation
        Task { @MainActor in
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted, generation == startedGeneration, isListening else {
                if generation == startedGeneration { isListening = false }
                return
            }
            await beginTranscription(generation: startedGeneration)
        }
    }

    func stop() {
        generation += 1
        isListening = false
        inputBuilder?.finish()
        inputBuilder = nil
        // Stop but keep the engine instance — re-creating AVAudioEngine per
        // session is the flaky path for CoreAudio's remote-IO bridge.
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        if let analyzer {
            Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
        }
        analyzer = nil
        resultsTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginTranscription(generation startedGeneration: Int) async {
        // The dictation module for the user's language, on the local
        // keyboard-dictation models.
        let supported = await DictationTranscriber.supportedLocales
        guard let locale = supported.first(where: {
            $0.identifier(.bcp47) == Locale.current.identifier(.bcp47)
        }) ?? supported.first(where: {
            $0.language.languageCode == Locale.current.language.languageCode
        }) else {
            isListening = false
            return
        }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)

        do {
            // First run may download the locale's model — everything stays on
            // the device afterwards.
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installation.downloadAndInstall()
            }
        } catch {
            isListening = false
            return
        }

        guard generation == startedGeneration, isListening else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            isListening = false
            return
        }

        let engine = audioEngine ?? AVAudioEngine()
        audioEngine = engine
        let inputNode = engine.inputNode
        let tapFormat = inputNode.outputFormat(forBus: 0)
        // No usable input (headless simulator, mic revoked at the OS level):
        // installing a tap with a 0 Hz format raises an NSException.
        guard tapFormat.sampleRate > 0, tapFormat.channelCount > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            isListening = false
            return
        }

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            isListening = false
            return
        }

        let (inputSequence, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputBuilder = builder

        // The tap fires on the audio thread. The converter and continuation
        // are used from there exclusively once installed.
        nonisolated(unsafe) let converter = AVAudioConverter(from: tapFormat, to: analyzerFormat)
        let needsConversion = tapFormat != analyzerFormat
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: tapFormat) { buffer, _ in
            if !needsConversion {
                builder.yield(AnalyzerInput(buffer: buffer))
                return
            }
            guard let converter else { return }
            let ratio = analyzerFormat.sampleRate / tapFormat.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 16)
            guard let converted = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
            var consumed = false
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, inputStatus in
                if consumed {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard conversionError == nil, converted.frameLength > 0 else { return }
            builder.yield(AnalyzerInput(buffer: converted))
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            builder.finish()
            inputBuilder = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            isListening = false
            return
        }

        audioEngine = engine

        // Volatile results replace the tail; finalized results accumulate.
        resultsTask = Task { @MainActor [weak self] in
            var finalized = ""
            do {
                for try await result in transcriber.results {
                    guard let self, self.generation == startedGeneration else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finalized += text
                        transcript = finalized
                    } else {
                        transcript = finalized + text
                    }
                }
            } catch {
                // Analysis failed or was torn down — the stop path owns state.
            }
        }

        let newAnalyzer = SpeechAnalyzer(modules: [transcriber])
        analyzer = newAnalyzer
        do {
            try await newAnalyzer.start(inputSequence: inputSequence)
        } catch {
            guard generation == startedGeneration else { return }
            stop()
        }
    }
}

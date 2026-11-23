import SwiftData
import SwiftUI

struct HelpView: View {
    @Query private var substanceColors: [SubstanceColor]
    @Query private var recentEntries: [DoseEntry]
    @Environment(\.appNavigator) private var navigator
    @State private var copiedSummary = false
    @State private var copiedResetTask: Task<Void, Never>?
    @State private var showShareSession = false
    @State private var activeSubstances: [ActiveSubstance] = []
    /// Resolved once per data change in `.task`, not on every `body` pass — the
    /// computation does a `SubstanceLibrary` (GRDB) lookup per recent dose.
    @State private var activeCategories: [SubstanceCategory] = []
    /// Each recent dose's title (``DoseTitle``), keyed by dose id, so a branded
    /// dose reads "Concerta" in the list.
    @State private var entryTitles: [UUID: String] = [:]

    init() {
        let cutoff = Date.now.addingTimeInterval(-72 * 3_600)
        _recentEntries = Query(
            filter: #Predicate<DoseEntry> { $0.timestamp > cutoff },
            sort: \DoseEntry.timestamp,
            order: .reverse,
        )
    }

    private var last24hEntries: [DoseEntry] {
        let cutoff = Date.now.addingTimeInterval(-24 * 3_600)
        return recentEntries.filter { $0.timestamp > cutoff }
    }

    /// Recompute token: the dose-log revision plus the color assignments.
    private var refreshToken: Int {
        var hasher = Hasher()
        hasher.combine(DoseLogService.shared.revision)
        hasher.combine(ColorsFingerprint.make(substanceColors))
        return hasher.finalize()
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    reassuranceSection
                    emergencySection
                    if !activeSubstances.isEmpty {
                        activeSubstancesSection
                    }
                    if !activeCategories.isEmpty {
                        recoverySection
                    }
                    if !last24hEntries.isEmpty {
                        recentDosesSection
                    }
                    if !activeSubstances.isEmpty || !last24hEntries.isEmpty {
                        copySection
                    }
                }
                .listRowBackground(CardBackground())
            }
            .themedPage()
            .sheet(isPresented: $showShareSession) {
                SessionShareSheet(
                    title: String(localized: "Current Session"),
                    dateText: Date.now.formatted(date: .abbreviated, time: .omitted),
                    entries: shareableEntries,
                    colors: substanceColors,
                    stackRedoses: true,
                )
            }
            .navigationTitle("Get Help")
            .task(id: refreshToken) {
                await SubstanceStore.shared.ensureAllLoaded()
                activeSubstances = ActiveSubstanceCalculator.compute(
                    from: recentEntries,
                    colorMap: substanceColors.colorMap,
                )
                activeCategories = ComedownGuide.recentGuidedCategories(
                    in: recentEntries,
                    cutoff: Date.now.addingTimeInterval(-48 * 3_600),
                )
                entryTitles = Dictionary(
                    recentEntries.map { ($0.id, DoseTitle.resolve(for: $0)) },
                    uniquingKeysWith: { first, _ in first },
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { navigator.dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close"))
                }
            }
        }
    }

    // MARK: - Reassurance

    private var reassuranceSection: some View {
        Section {
            VStack(spacing: Spacing.xl) {
                Image(systemName: "heart.fill")
                    .font(.piru(.largeTitle))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                Text("You don't have to do this alone")
                    .font(.piru(.title2, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)

                Text("Piru can't assess how you are. The people at the numbers below can.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)

                Text("Take a deep breath.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .accessibilityElement(children: .combine)

            groundingTip(
                icon: "music.note",
                color: .purple,
                title: "Put on familiar music",
                detail: activeCategories.contains(.psychedelic)
                    ? "Music you know well is one of the most powerful grounding tools, especially during a psychedelic experience."
                    : "Familiar songs can ground you and bring comfort. Pick something you know well.",
            )

            groundingTip(
                icon: "person.2.fill",
                color: .pink,
                title: "Call a friend or family member",
                detail: "Someone who knows you can help more than you\u{2019}d expect. You don\u{2019}t have to explain everything. Just hearing a familiar voice helps.",
            )
        }
    }

    // MARK: - Grounding Tips

    private func groundingTip(icon: String, color: Color, title: LocalizedStringResource, detail: LocalizedStringResource) -> some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .captionSecondary()
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.xxs)
    }

    // MARK: - Recovery Guide

    private var recoverySection: some View {
        Section {
            ForEach(activeCategories, id: \.self) { category in
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: category.icon)
                            .foregroundStyle(category.labelColor)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(category.displayName)
                            .sectionLabel()
                    }

                    let guide = ComedownGuide.guide(for: category)
                    ForEach(Array(guide.rightNow.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Text("\u{2022}")
                                .foregroundStyle(Theme.secondaryLabel)
                            Text(tip)
                                .captionSecondary()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }

            NavigationLink {
                ComedownGuideView()
            } label: {
                Label("View Full Recovery Guide", systemImage: "heart.text.clipboard")
                    .font(.subheadline)
            }
        } header: {
            Text("Recovering Now")
        } footer: {
            Text("Showing the guide for the classes you logged in the last 48 hours. Tap above for the full guide.")
        }
    }

    // MARK: - Emergency Services

    private var regionCode: String {
        EmergencyServices.regionCode
    }

    private var regionName: String? {
        Locale.current.localizedString(forRegionCode: regionCode)
    }

    private var emergencySection: some View {
        Section {
            ForEach(EmergencyServices.services(for: regionCode)) { service in
                if let destination = URL(string: service.url) {
                    Link(destination: destination) {
                        HStack {
                            Image(systemName: service.systemImage)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(service.tint)
                                .frame(width: 28)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(service.title)
                                    .font(.subheadline.weight(.medium))
                                Text(service.detail)
                                    .captionSecondary()
                            }

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.tertiaryLabel)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        } header: {
            if let name = regionName {
                Text("Emergency Services: \(name)")
            } else {
                Text("Emergency Services")
            }
        }
    }

    // MARK: - Active Substances

    private var activeSubstancesSection: some View {
        Section {
            ForEach(activeSubstances) { substance in
                HStack(spacing: Spacing.lg) {
                    Circle()
                        .fill(substance.color)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(substance.name)
                            .font(.subheadline.weight(.medium))
                        let remaining = Int((1 - substance.eliminatedFraction) * 100)
                        Text("\(substance.totalDosed.doseFormatted) \(substance.unit) total \u{00B7} est. ~\(remaining)% remaining")
                            .captionSecondary()
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Modeled as Active")
        } footer: {
            Text("Estimates from pharmacokinetic modeling.")
        }
    }

    // MARK: - Recent Doses

    private func colorFor(_ entry: DoseEntry) -> Color {
        substanceColors.colorMap[entry.substance.lowercased()] ?? Theme.accent
    }

    private var recentDosesSection: some View {
        Section("Recent Entries (24h)") {
            ForEach(last24hEntries) { entry in
                HStack(spacing: Spacing.xl) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorFor(entry))
                        .frame(width: 4, height: 40)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entryTitles[entry.id] ?? CustomSubstanceStore.shared.displayName(for: entry.substance))
                            .sectionLabel()

                        HStack(spacing: Spacing.xs) {
                            Text("\(entry.amountDisplay) \(entry.unit)")
                            Middot()
                                .foregroundStyle(Theme.tertiaryLabel)
                            Text(entry.route.localizedName)
                        }
                        .captionSecondary()
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(entry.timestamp, style: .time)
                            .font(.subheadline.weight(.medium))
                        Text(entry.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryLabel)
                    }
                }
                .padding(.vertical, Spacing.xxs)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Copy Summary

    private var copySection: some View {
        Section {
            Button {
                PlatformPasteboard.copy(generateSummaryText())
                copiedSummary = true
                copiedResetTask?.cancel()
                copiedResetTask = Task(name: "Reset copied flash") {
                    try? await Task.sleep(for: UITiming.copiedFlash)
                    guard !Task.isCancelled else { return }
                    copiedSummary = false
                }
            } label: {
                HStack {
                    Spacer()
                    Label(
                        copiedSummary ? "Copied" : "Copy Summary for Emergency Services",
                        systemImage: copiedSummary ? "checkmark.circle.fill" : "doc.on.doc",
                    )
                    .font(.subheadline.weight(.medium))
                    .animation(.none, value: copiedSummary)
                    Spacer()
                }
            }
            if !shareableEntries.isEmpty {
                Button {
                    showShareSession = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Share Current State…", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                }
            }
        } footer: {
            Text("Copies a plain-text summary of substances and recent doses to share with emergency responders.")
        }
    }

    /// Currently-active doses — the session a "Share Current State" hands off.
    private var shareableEntries: [DoseEntry] {
        InteractionChecker.activeEntries(from: recentEntries)
    }

    // MARK: - Summary Text Generation

    private func generateSummaryText() -> String {
        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        lines.append("SUBSTANCE SUMMARY")
        lines.append("Generated: \(formatter.string(from: .now))")
        lines.append("")

        if !activeSubstances.isEmpty {
            lines.append("CURRENTLY ACTIVE:")
            for substance in activeSubstances {
                let remaining = Int((1 - substance.eliminatedFraction) * 100)
                lines.append("- \(substance.name): \(substance.totalDosed.doseFormatted) \(substance.unit) total (est. ~\(remaining)% remaining)")
                for dose in substance.doses {
                    lines.append("  \(dose.amount.doseFormatted) \(substance.unit) at \(formatter.string(from: dose.timestamp))")
                }
            }
            lines.append("")
        }

        let entries = last24hEntries
        if !entries.isEmpty {
            lines.append("RECENT DOSES (LAST 24 HOURS):")
            for entry in entries {
                // Lead with the canonical name — this is read by someone
                // treating the person, and a brand or a non-English alias isn't
                // always actionable. The user's own word follows when it
                // differs, so they can still recognize their own log. Raw
                // `entry.substance` was neither: it's whatever string was typed,
                // which may be an alias the catalog has since renamed.
                let canonical = SubstanceLibrary.lookup(entry.substance)?.displayTitle ?? entry.substance
                let logged = DoseTitle.resolve(for: entry)
                let name = logged.caseInsensitiveCompare(canonical) == .orderedSame
                    ? canonical
                    : "\(canonical) (logged as \(logged))"
                var line = "- \(name) \(entry.amountDisplay) \(entry.unit) \(String(localized: entry.route.localizedName).lowercased()) at \(formatter.string(from: entry.timestamp))"
                if let notes = entry.notes, !notes.isEmpty {
                    line += " (\(notes))"
                }
                lines.append(line)
            }
        }

        if activeSubstances.isEmpty, entries.isEmpty {
            lines.append("No active substances or recent doses recorded.")
        }

        lines.append("")
        lines.append("Generated by Piru. Estimates are approximate.")
        return lines.joined(separator: "\n")
    }
}

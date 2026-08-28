import SwiftUI

/// The feature tour: a paged carousel of four faux-app "screenshots" rendered entirely in
/// SwiftUI (so they localize, theme, and never go stale), each captioned with what the tab does.
/// The Journal and Library mocks reuse the *real* app components (`TimelineGraphView`,
/// `FamilyGradientCard`, `MoleculeView`) so the preview matches the app exactly. A single
/// "Continue" advances the whole flow — the pages are browsable, not a gate.
struct OnboardingFeatureTour: View {
    @Environment(\.onboardingNav) private var nav
    @State private var page = 0

    private let pages = FeatureTourPage.all

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    tourPage(item).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.smooth, value: page)

            HStack(spacing: 7) {
                ForEach(0 ..< pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Theme.accent : Theme.accent.opacity(0.2))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Page \(page + 1) of \(pages.count)"))

            GlassPillButton(title: "Continue", action: nav.advance)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
    }

    private func tourPage(_ item: FeatureTourPage) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            PhoneMock { item.mock }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Text(item.title)
                    .font(.title2.weight(.bold))
                Text(item.caption)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 8)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Page model

struct FeatureTourPage: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let caption: LocalizedStringResource
    let mock: AnyView

    static let all: [FeatureTourPage] = [
        FeatureTourPage(
            id: "journal",
            title: "Log it in seconds",
            caption: "Every dose lands on a timeline so you can see what's active — and when it fades.",
            mock: AnyView(JournalMock()),
        ),
        FeatureTourPage(
            id: "library",
            title: "1,500+ substances",
            caption: "Browse by family — dosing, duration, effects, and interactions, sourced and cited.",
            mock: AnyView(LibraryMock()),
        ),
        FeatureTourPage(
            id: "tools",
            title: "Tools that have your back",
            caption: "Check interactions, model tolerance, track your stock, and dose liquids safely.",
            mock: AnyView(ToolsMock()),
        ),
        FeatureTourPage(
            id: "insights",
            title: "See your patterns",
            caption: "Usage over time, times of day, and what's in your system right now — at a glance.",
            mock: AnyView(InsightsMock()),
        ),
    ]
}

// MARK: - Phone frame

/// A device-ish frame that makes the mock read as an app screenshot: rounded bezel, soft shadow,
/// a faux status bar, and a fixed iPhone-like aspect ratio (taller than it is wide) so every tour
/// card is the same shape rather than a squat square.
struct PhoneMock<Content: View>: View {
    @ViewBuilder var content: Content

    private static var mockWidth: CGFloat {
        244
    }
    private static var mockHeight: CGFloat {
        460
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            content
                .padding(.horizontal, 12)
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .frame(width: Self.mockWidth, height: Self.mockHeight)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1),
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
        .accessibilityHidden(true)
    }

    private var statusBar: some View {
        HStack {
            Text(verbatim: "9:41")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.75")
            }
            .accessibilityHidden(true)
            .font(.system(size: 9))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Mock palette

private enum MockPalette {
    static let pink = Color(red: 0.94, green: 0.35, blue: 0.55)
    static let blue = Color(red: 0.30, green: 0.55, blue: 0.95)
    static let green = Color(red: 0.30, green: 0.72, blue: 0.52)
    static let orange = Color(red: 0.96, green: 0.62, blue: 0.26)
    static let purple = Color(red: 0.60, green: 0.45, blue: 0.90)
    static let teal = Color(red: 0.18, green: 0.66, blue: 0.66)
    static let yellow = Color(red: 0.96, green: 0.80, blue: 0.25)
}

private struct MockTitle: View {
    let text: LocalizedStringResource
    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Journal mock (real timeline graph)

private struct JournalMock: View {
    @State private var now = Date()

    private var states: [ActiveSubstanceState] {
        [
            ActiveSubstanceState(
                substanceName: "Ibuprofen", colorHex: "4C8CF2",
                doseTimestamp: now.addingTimeInterval(-160 * 60),
                amount: 400, unit: "mg", route: "oral",
                onsetEndMinutes: 30, comeupEndMinutes: 75, peakEndMinutes: 120,
                offsetEndMinutes: 360, afterglowEndMinutes: 420, totalMinutes: 420,
                doseIntensity: 0.55,
            ),
            ActiveSubstanceState(
                substanceName: "Caffeine", colorHex: "F0598C",
                doseTimestamp: now.addingTimeInterval(-80 * 60),
                amount: 80, unit: "mg", route: "oral",
                onsetEndMinutes: 15, comeupEndMinutes: 45, peakEndMinutes: 80,
                offsetEndMinutes: 240, afterglowEndMinutes: 300, totalMinutes: 300,
                doseIntensity: 0.8,
            ),
            ActiveSubstanceState(
                substanceName: "Alcohol", colorHex: "F59E42",
                doseTimestamp: now.addingTimeInterval(-15 * 60),
                amount: 2, unit: "drinks", route: "oral",
                onsetEndMinutes: 10, comeupEndMinutes: 30, peakEndMinutes: 55,
                offsetEndMinutes: 150, afterglowEndMinutes: 210, totalMinutes: 210,
                doseIntensity: 0.7, tachyphylaxis: 0.3,
            ),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MockTitle(text: "Journal")
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "Today")
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(MockPalette.pink).frame(width: 8, height: 8)
                    Circle().fill(MockPalette.orange).frame(width: 8, height: 8)
                    Circle().fill(MockPalette.blue).frame(width: 8, height: 8)
                    Text(verbatim: "Caffeine · Alcohol · Ibuprofen")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                TimelineGraphView(
                    substances: states,
                    currentTime: now,
                    compact: false,
                    showNowIndicator: true,
                    dayBounded: true,
                    synchronous: true,
                )
                .frame(height: 180)
                .allowsHitTesting(false)
            }
            .padding(12)
            .themeCard(cornerRadius: 16)
        }
    }
}

// MARK: - Library mock (real gradient family cards + molecules)

private struct LibraryMock: View {
    private struct Family {
        let color: Color
        let molecule: String
        let icon: String
        let title: LocalizedStringResource
        let samples: String
        let count: String
    }

    private let families: [Family] = [
        Family(
            color: Color(red: 0.28, green: 0.46, blue: 0.74),
            molecule: "caffeine",
            icon: "flame.fill",
            title: "Common",
            samples: "Caffeine · Alcohol · Nicotine",
            count: "20",
        ),
        Family(
            color: .orange,
            molecule: "amphetamine",
            icon: "bolt.fill",
            title: "Stimulants",
            samples: "Amphetamine · Cocaine · Modafinil",
            count: "237",
        ),
        Family(
            color: .pink,
            molecule: "mdma",
            icon: "heart.fill",
            title: "Empathogens",
            samples: "MDMA · Mephedrone · 3-MMC",
            count: "68",
        ),
        Family(
            color: .green,
            molecule: "thc",
            icon: "leaf.fill",
            title: "Cannabinoids",
            samples: "Cannabis · HHC · Delta-8",
            count: "34",
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MockTitle(text: "Library")
            ForEach(Array(families.enumerated()), id: \.offset) { _, family in
                card(family)
            }
        }
    }

    private func card(_ family: Family) -> some View {
        FamilyGradientCard(color: family.color, cornerRadius: 18, padding: 12) {
            MoleculeView(key: family.molecule)
                .frame(width: 108, height: 108)
                .opacity(0.5)
                .offset(x: 20, y: -6)
        } content: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Image(systemName: family.icon)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    HStack(spacing: 2) {
                        Text(verbatim: family.count).font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                Text(family.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text(verbatim: family.samples)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Tools mock

private struct ToolsMock: View {
    private let tools: [(String, LocalizedStringResource, Color)] = [
        ("arrow.triangle.branch", "Interactions", MockPalette.pink),
        ("chart.line.downtrend.xyaxis", "Tolerance", MockPalette.blue),
        ("archivebox.fill", "Inventory", MockPalette.purple),
        ("timer", "Half-Life", MockPalette.green),
        ("eyedropper.halffull", "Volumetric", MockPalette.orange),
        ("cross.case.fill", "Recovery", MockPalette.teal),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MockTitle(text: "Tools")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(tools, id: \.1.key) { tool in
                    VStack(spacing: 8) {
                        Image(systemName: tool.0)
                            .font(.system(size: 20))
                            .foregroundStyle(tool.2)
                            .accessibilityHidden(true)
                        Text(tool.1)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .themeCard(cornerRadius: 16)
                }
            }
        }
    }
}

// MARK: - Insights mock (usage bar chart)

private struct InsightsMock: View {
    private struct Bar: Identifiable {
        let id = UUID()
        let label: LocalizedStringResource
        let count: Int
        let color: Color
    }

    private let bars: [Bar] = [
        Bar(label: "Morning", count: 66, color: MockPalette.orange),
        Bar(label: "Afternoon", count: 27, color: MockPalette.yellow),
        Bar(label: "Evening", count: 69, color: MockPalette.purple),
        Bar(label: "Night", count: 6, color: MockPalette.blue),
    ]

    private var maxCount: Int {
        bars.map(\.count).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MockTitle(text: "Insights")
            VStack(alignment: .leading, spacing: 12) {
                Text("Time of Day")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                chart
            }
            .padding(14)
            .themeCard(cornerRadius: 16)

            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent)
                Text(verbatim: "440 entries · 4.9/day")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .padding(14)
            .themeCard(cornerRadius: 16)
        }
    }

    private var chart: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(bars) { bar in
                VStack(spacing: 6) {
                    Text(verbatim: "\(bar.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondaryLabel)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(bar.color)
                        .frame(height: max(6, 150 * CGFloat(bar.count) / CGFloat(maxCount)))
                    Text(bar.label)
                        .font(.system(size: 8.5))
                        .foregroundStyle(Theme.secondaryLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 184, alignment: .bottom)
    }
}

#Preview {
    OnboardingFeatureTour()
        .background(Theme.background)
}

import SwiftUI

/// What the options menu shows **below** the always-on combined recovery chart: per-mechanism **cards**
/// or per-substance **rows**. The combined chart shows in both; this only switches the detail.
enum ToleranceDetailMode: CaseIterable, Identifiable {
    case perReceptor
    case perSubstance

    var id: Self {
        self
    }

    var title: LocalizedStringResource {
        switch self {
        case .perReceptor: "By mechanism"
        case .perSubstance: "By substance"
        }
    }
}

/// The single toolbar button's popover, modeled on Mail's view-options menu: a thumbnail picker for the
/// display mode across the top (two line-art phones with a radio each), a divider, then the detail-tier
/// checklist. Selecting keeps the popover open, so mode and tier can both be changed in one visit.
struct ToleranceOptionsMenu: View {
    @Binding var mode: ToleranceDetailMode
    @Binding var tier: UserProfile

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 28) {
                ForEach(ToleranceDetailMode.allCases) { option in
                    modeColumn(option)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            VStack(spacing: 0) {
                ForEach(UserProfile.allCases) { option in
                    Button {
                        tier = option
                    } label: {
                        tierRow(option)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 280)
    }

    private func modeColumn(_ option: ToleranceDetailMode) -> some View {
        let selected = mode == option
        return Button {
            mode = option
        } label: {
            VStack(spacing: 8) {
                MenuPhoneThumbnail(selected: selected, sketch: PhoneThumbnailArt.sketch(for: option))
                    .frame(width: 72, height: 148) // aspect 0.486 — the iPhone 17 bezel
                Text(option.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                radio(selected: selected)
                    .frame(width: 22, height: 22)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option.title))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func radio(selected: Bool) -> some View {
        ZStack {
            if selected {
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5)
            }
        }
    }

    private func tierRow(_ option: UserProfile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .opacity(tier == option ? 1 : 0)
                .frame(width: 16)
            Image(systemName: option.icon)
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            Text(option.displayName)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityAddTraits(tier == option ? [.isSelected] : [])
    }
}

/// The tolerance modes' screen sketches for ``MenuPhoneThumbnail`` — stacked cards for **By mechanism**,
/// list rows for **By substance**.
enum PhoneThumbnailArt {
    static func sketch(for mode: ToleranceDetailMode) -> (GraphicsContext, CGRect, Color) -> Void {
        switch mode {
        case .perReceptor: drawCards
        case .perSubstance: drawRows
        }
    }

    /// Three stacked card bars.
    private static func drawCards(_ context: GraphicsContext, in rect: CGRect, color: Color) {
        let count = 3
        let gap = rect.height * 0.14
        let h = (rect.height - gap * CGFloat(count - 1)) / CGFloat(count) * 0.6
        for i in 0 ..< count {
            let y = rect.minY + CGFloat(i) * (h + gap)
            let bar = CGRect(x: rect.minX, y: y, width: rect.width, height: h)
            context.fill(Path(roundedRect: bar, cornerRadius: h * 0.28), with: .color(color))
        }
    }

    /// Four list rows: a leading dot + a line each. Rows are laid top-down with the same gap model as the
    /// cards, so the first row begins at `rect.minY` — matching the cards' top padding.
    private static func drawRows(_ context: GraphicsContext, in rect: CGRect, color: Color) {
        let count = 4
        let gap = rect.height * 0.12
        let rowH = (rect.height - gap * CGFloat(count - 1)) / CGFloat(count)
        let dot = min(rect.width * 0.15, rowH)
        let lineH = max(2, rowH * 0.42)
        for i in 0 ..< count {
            let cy = rect.minY + CGFloat(i) * (rowH + gap) + rowH / 2
            context.fill(Path(ellipseIn: CGRect(x: rect.minX, y: cy - dot / 2, width: dot, height: dot)), with: .color(color))
            let lineRect = CGRect(x: rect.minX + dot * 1.6, y: cy - lineH / 2, width: rect.width - dot * 1.6, height: lineH)
            context.fill(Path(roundedRect: lineRect, cornerRadius: lineH / 2), with: .color(color))
        }
    }
}

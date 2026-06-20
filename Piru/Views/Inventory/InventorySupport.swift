import SwiftUI

// MARK: - Stock status

/// The health of an item's stock. Drives color, which — per the HIG rule the
/// spec adopts — carries meaning *only* for Low/Out; a healthy supply reads
/// neutral.
enum StockStatus {
    case ok
    case low
    case out

    /// Number / label color. Neutral (`primary`) when healthy so color is
    /// reserved for the states that need attention.
    var numberColor: Color {
        switch self {
        case .ok: .primary
        case .low: .orange
        case .out: .red
        }
    }

    /// Supply-bar fill color. Healthy is a neutral fill, not green.
    var barTint: Color {
        switch self {
        case .ok: Color.primary.opacity(0.35)
        case .low: .orange
        case .out: .red
        }
    }
}

extension InventoryItem {
    /// Healthy / low / out, derived from the cached quantity and threshold.
    var stockStatus: StockStatus {
        if currentQuantity <= 0 { return .out }
        if let threshold = lowStockThreshold, threshold > 0, currentQuantity <= threshold { return .low }
        return .ok
    }

    /// A baseline is "set" only when it's a positive number; `nil` or `0` mean
    /// the supply bar is disabled.
    var hasBaseline: Bool {
        (baselineQuantity ?? 0) > 0
    }

    /// Fraction of the baseline currently on hand, clamped to `0...1`. `nil` when
    /// no baseline is set (no bar).
    var fillFraction: Double? {
        guard let baseline = baselineQuantity, baseline > 0 else { return nil }
        return min(1, max(0, currentQuantity / baseline))
    }

    /// Substance with its salt inline, so variants don't read as duplicates.
    ///
    /// The stored ``substance`` is the canonical name (so doses match); for
    /// display we resolve it to the library's presentation name — the same one
    /// the journal and quick-log show (e.g. canonical "Bromoketamine" →
    /// "2-Br-DCK") — falling back to the stored name for custom substances.
    @MainActor
    var displayTitle: String {
        let resolved = SubstanceLibrary.lookup(substance)?.displayTitle ?? substance
        if let salt = saltForm, !salt.isEmpty {
            return "\(resolved) · \(salt)"
        }
        return resolved
    }
}

// MARK: - Run-out formatting (shared by detail + substance card)

/// One-line run-out copy: "~N doses · ~N weeks left" (dropping the doses part
/// when no dose size is set).
@MainActor
func inventoryRunOutLine(for item: InventoryItem, runOut: InventoryMath.RunOut) -> String {
    let humanized = inventoryHumanizeDays(runOut.daysLeft)
    if let doses = InventoryMath.dosesLeft(for: item) {
        return String(localized: "~\(doses) doses · \(humanized) left")
    }
    return String(localized: "\(humanized) left")
}

/// Humanize a days-left figure: `< 14` → days, `< 60` → weeks, else months.
func inventoryHumanizeDays(_ days: Double) -> String {
    if days < 14 {
        return String(localized: "~\(Int(days.rounded())) days")
    } else if days < 60 {
        return String(localized: "~\(Int((days / 7).rounded())) weeks")
    }
    return String(localized: "~\(Int((days / 30).rounded())) months")
}

// MARK: - Supply bar

/// A thin status-tinted supply bar. Shown only when an item has a baseline.
struct InventorySupplyBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(3, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Substance dot

/// The small colored dot identifying a substance, matching the journal's dots.
struct SubstanceDot: View {
    let name: String
    let colorMap: [String: Color]
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(SubstancePalette.color(for: name, colorMap: colorMap))
            .frame(width: size, height: size)
    }
}

import SwiftUI

/// The **efficacy axis** — how far the receptor switches on once occupied, not how tightly the drug
/// binds and not morphine-equivalence. It is the axis that separates a full agonist from a partial
/// one, the axis respiratory depression tracks, and the axis that explains why synthetic
/// cannabinoids hurt people and cannabis mostly doesn't.
///
/// Two marker states, and the distinction is the whole point:
/// - **solid** — measured in the same experiment as this compound, so it can be ranked against it;
/// - **hollow** — the same measure against the same reference agonist, from a *different* study.
///
/// τ and Emax never share an axis. Morphine is 94 % of DAMGO by Emax and τ 0.18; plotting the two
/// together renders every clinical opioid a full agonist, which is exactly the error the
/// ``SignatureComparability`` gate exists to prevent.
struct EfficacyAxisView: View {
    let model: EfficacyAxisModel
    let accent: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let headline = model.headline {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.14)))
            }

            if model.isStaticReadout {
                // §C: a ladder with a single tier is not a ladder. Degrade to a readout.
                EfficacyStaticReadout(model: model, accent: accent)
            } else if dynamicTypeSize.isAccessibilitySize {
                // At AX sizes the tick labels cannot avoid the axis, so the axis becomes a list.
                EfficacyMarkList(model: model, accent: accent)
            } else {
                EfficacyAxisTrack(model: model, accent: accent)
            }

            SignatureCaption(provenance: model.provenance, isGated: model.isGated)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The drawn axis

private struct EfficacyAxisTrack: View {
    let model: EfficacyAxisModel
    let accent: Color

    @Environment(\.layoutDirection) private var layoutDirection

    private static let inset: CGFloat = 20
    private static let labelWidth: CGFloat = 82
    private static let rowHeight: CGFloat = 13
    private static let trackY: CGFloat = 42
    private static let endLabelY: CGFloat = 84
    private static let height: CGFloat = 98

    var body: some View {
        // One `ZStack` rather than a stack of rows: every mark, label and end-cap is placed against
        // the same origin, so the staggered label rows can never drift into the axis line.
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                track(width: width)
                ForEach(clusters) { cluster in
                    marker(cluster, width: width)
                }
                ForEach(placedLabels(width: width), id: \.cluster.id) { placed in
                    label(placed.cluster, row: placed.row, width: width)
                }
                endLabels
                    .frame(width: width, alignment: .leading)
                    .offset(y: Self.endLabelY)
            }
            .frame(width: width, height: Self.height, alignment: .topLeading)
            // Pin the plot to LTR and mirror by hand. Otherwise the auto-flip applies to
            // `.offset`-placed marks but is compounded by the manual mirroring the axis needs, and
            // the end caps end up labeling the wrong ends — verified on device in an RTL locale.
            .environment(\.layoutDirection, .leftToRight)
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("Efficacy axis", comment: "Accessibility label for the partial-to-full efficacy axis"),
        )
        .accessibilityValue(Text(accessibilityValue))
    }

    private func track(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Theme.secondaryLabel.opacity(0.18))
                .frame(width: max(0, width - Self.inset * 2), height: 7)
                .offset(x: Self.inset, y: Self.trackY - 3.5)
            Capsule()
                .fill(accent.opacity(0.75))
                .frame(width: max(0, filledWidth(width)), height: 7)
                .offset(x: layoutDirection == .rightToLeft
                    ? x(model.focus.percent, width: width)
                    : Self.inset, y: Self.trackY - 3.5)
        }
    }

    private func filledWidth(_ width: CGFloat) -> CGFloat {
        abs(x(model.focus.percent, width: width) - x(0, width: width))
    }

    @ViewBuilder
    private func marker(_ cluster: Cluster, width: CGFloat) -> some View {
        let px = x(cluster.percent, width: width)
        Group {
            Rectangle()
                .fill(cluster.isFocus ? accent : Theme.secondaryLabel.opacity(0.55))
                .frame(width: cluster.isFocus ? 3 : 1.4, height: 18)
                .offset(x: px - (cluster.isFocus ? 1.5 : 0.7), y: Self.trackY - 9)
            Circle()
                .fill(cluster.isGated ? (cluster.isFocus ? Color(.systemBackground) : Theme.secondaryLabel.opacity(0.55)) : Color(.systemBackground))
                .overlay(
                    Circle().strokeBorder(
                        cluster.isFocus ? accent : Theme.secondaryLabel.opacity(0.55),
                        lineWidth: cluster.isFocus ? 4 : 1.5,
                    ),
                )
                .frame(width: cluster.isFocus ? 17 : 9, height: cluster.isFocus ? 17 : 9)
                .offset(
                    x: px - (cluster.isFocus ? 8.5 : 4.5),
                    y: Self.trackY - (cluster.isFocus ? 8.5 : 4.5),
                )
        }
    }

    private func label(_ cluster: Cluster, row: Int, width: CGFloat) -> some View {
        let px = min(max(x(cluster.percent, width: width), Self.labelWidth / 2), width - Self.labelWidth / 2)
        // Rows 0–1 sit above the track, rows 2–3 below it, innermost first.
        let y: CGFloat = switch row {
        case 0: Self.trackY - 15 - Self.rowHeight
        case 1: Self.trackY - 15 - Self.rowHeight * 2
        case 2: Self.trackY + 13
        default: Self.trackY + 13 + Self.rowHeight
        }
        return Text(cluster.name)
            .font(.system(size: 9.5, weight: cluster.isFocus ? .bold : .medium))
            .foregroundStyle(cluster.isFocus ? accent : Theme.secondaryLabel)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .multilineTextAlignment(.center)
            .frame(width: Self.labelWidth, height: Self.rowHeight)
            .offset(x: px - Self.labelWidth / 2, y: y)
    }

    /// Greedy two-above / two-below packing. τ crowds every clinical opioid into the leftmost fifth
    /// of the axis (buprenorphine 0.02 → morphine 0.18 of DAMGO), which is the *point* of plotting τ
    /// — so the labels have to stagger rather than the axis rescale away the finding.
    private func placedLabels(width: CGFloat) -> [(cluster: Cluster, row: Int)] {
        var rowRight: [CGFloat] = [-.greatestFiniteMagnitude, -.greatestFiniteMagnitude,
                                   -.greatestFiniteMagnitude, -.greatestFiniteMagnitude]
        var placed: [(cluster: Cluster, row: Int)] = []
        // Focus first so it always lands on an inner row, then left-to-right.
        let ordered = clusters.sorted { lhs, rhs in
            if lhs.isFocus != rhs.isFocus { return lhs.isFocus }
            return x(lhs.percent, width: width) < x(rhs.percent, width: width)
        }
        for cluster in ordered {
            let center = min(max(x(cluster.percent, width: width), Self.labelWidth / 2), width - Self.labelWidth / 2)
            let left = center - Self.labelWidth / 2
            let row = (0 ..< rowRight.count).first { rowRight[$0] < left - 3 }
                ?? rowRight.indices.min { rowRight[$0] < rowRight[$1] } ?? 0
            rowRight[row] = center + Self.labelWidth / 2
            placed.append((cluster, row))
        }
        return placed
    }

    /// The plot is pinned to LTR, so the two end caps are ordered explicitly rather than by an
    /// automatic flip — the zero end has to sit under the zero end of the track in both directions.
    private var endLabels: some View {
        let zero = String(localized: "no activation", comment: "Zero end of the efficacy axis")
        let isRTL = layoutDirection == .rightToLeft
        return HStack(spacing: 8) {
            Text(isRTL ? fullEndLabel : zero)
            Spacer(minLength: 4)
            Text(isRTL ? zero : fullEndLabel)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Theme.secondaryLabel)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// The right end is *full activation as this experiment defined it* — the reference agonist,
    /// which is 100 % by construction. Naming it keeps the ceiling from reading as an absolute.
    private var fullEndLabel: String {
        guard let reference = model.provenance.referenceAgonist, !reference.isEmpty else {
            return String(localized: "full activation", comment: "Right end of the efficacy axis")
        }
        return String(
            localized: "full activation · \(reference)",
            comment: "Right end of the efficacy axis, naming the reference agonist",
        )
    }

    private func x(_ percent: Double, width: CGFloat) -> CGFloat {
        let usable = max(0, width - Self.inset * 2)
        let fraction = min(1, max(0, percent / model.axisMaximum))
        let ltr = Self.inset + usable * fraction
        return layoutDirection == .rightToLeft ? width - ltr : ltr
    }

    /// Marks closer together than 5 % of the axis share one label, so a crowd of clinical opioids at
    /// τ 0.02–0.18 reads as "Buprenorphine · Tapentadol" instead of overlapping type.
    private var clusters: [Cluster] {
        var result: [Cluster] = []
        for mark in model.marks {
            if let index = result.firstIndex(where: {
                abs($0.percent - mark.percent) < model.axisMaximum * 0.05 && $0.isFocus == mark.isFocus
            }) {
                result[index].names.append(mark.name)
                result[index].isGated = result[index].isGated && mark.isGated
            } else {
                result.append(Cluster(
                    id: mark.id, names: [mark.name], percent: mark.percent,
                    isFocus: mark.isFocus, isGated: mark.isGated,
                ))
            }
        }
        return result
    }

    private var accessibilityValue: String {
        let focus = String(
            localized: "\(model.focus.name) at \(model.focus.valueText)",
            comment: "Efficacy axis accessibility value for the focused substance",
        )
        let peers = model.marks
            .filter { !$0.isFocus }
            .map { "\($0.name) \($0.valueText)" }
            .joined(separator: ", ")
        return peers.isEmpty ? focus : "\(focus). \(peers)"
    }

    private struct Cluster: Identifiable {
        let id: String
        var names: [String]
        let percent: Double
        let isFocus: Bool
        var isGated: Bool

        var name: String {
            names.joined(separator: " · ")
        }
    }
}

// MARK: - Degraded forms

/// §C: one mark is not a ladder. State the value and its class instead of drawing an axis with a
/// single tick on it.
private struct EfficacyStaticReadout: View {
    let model: EfficacyAxisModel
    let accent: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(model.focus.valueText)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(accent)
            Text("nothing comparable to rank it against", comment: "Efficacy axis degraded to a single readout")
                .font(.caption)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The axis as a list, for accessibility text sizes where tick labels would collide with the arc.
private struct EfficacyMarkList: View {
    let model: EfficacyAxisModel
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.marks.reversed()) { mark in
                HStack(spacing: 8) {
                    Text(mark.name)
                        .font(.subheadline.weight(mark.isFocus ? .bold : .regular))
                        .foregroundStyle(mark.isFocus ? accent : .primary)
                    Spacer(minLength: 6)
                    if !mark.isGated {
                        Image(systemName: "circle.dashed")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryLabel)
                            .accessibilityLabel(Text("different study", comment: "Hollow marker meaning"))
                    }
                    Text(mark.valueText)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(mark.isFocus ? accent : Theme.secondaryLabel)
                }
                .padding(.vertical, 5)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

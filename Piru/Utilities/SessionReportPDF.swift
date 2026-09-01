import CoreGraphics
import SwiftUI
import UIKit

// MARK: - Phase color (matches DosePhaseProgressBar so the export reads like the app)

private extension SessionStateExport.Phase {
    var color: Color {
        switch self {
        case .onset: Color(hex: "9B9BA1")
        case .comeup: Color(hex: "3A8DEF")
        case .peak: Color(hex: "34C759")
        case .offset: Color(hex: "FF9F0A")
        case .after: Color(hex: "9B9BA1")
        }
    }
}

// MARK: - PDF renderer

/// A snapshot render of one live or historical session, triggered from the
/// session share sheet (see ``PDFReportGenerator`` for the full medical report).
@MainActor
enum SessionReportPDF {
    /// US-Letter width; height grows with content (single tall page — the active
    /// session is short, and a digital share/archive prints fine).
    private static let pageWidth: CGFloat = 612

    static func render(_ export: SessionStateExport) -> Data {
        let content = SessionReportView(export: export)
            .frame(width: pageWidth)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: pageWidth, height: nil)

        let pdfData = NSMutableData()
        renderer.render { size, drawInContext in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
            else { return }
            context.beginPDFPage(nil)
            drawInContext(context)
            context.endPDFPage()
            context.closePDF()
        }
        return pdfData as Data
    }
}

// MARK: - Report view

struct SessionReportView: View {
    let export: SessionStateExport

    private let ink = Color(hex: "201519")
    private let ink2 = Color(hex: "6B5860")
    private let hair = Color(hex: "E7D8DE")
    private let panel = Color(hex: "FBF4F6")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !export.interactions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(export.interactions) { line in
                        interactionCallout(line)
                    }
                }
                .padding(.top, 16)
            }

            sectionHeader(export.isLive ? "Right now — subjective state" : "Doses")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(export.substances.enumerated()), id: \.element.id) { index, s in
                    subjectiveRow(s)
                        .overlay(alignment: .top) {
                            if index > 0 { Rectangle().fill(hair).frame(height: 1) }
                        }
                }
            }
            phaseLegend

            if !export.notes.isEmpty {
                sectionHeader("Notes")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(export.notes.enumerated()), id: \.element.id) { index, note in
                        noteRow(note)
                            .overlay(alignment: .top) {
                                if index > 0 { Rectangle().fill(hair).frame(height: 1) }
                            }
                    }
                }
            }

            sectionHeader("Elimination")
            VStack(spacing: 12) {
                ForEach(export.eliminations) { group in
                    eliminationCard(group)
                }
            }

            footer
        }
        .padding(42)
        .background(Color.white)
        .foregroundStyle(ink)
        .font(.system(size: 13))
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(export.isLive ? "Session Snapshot" : "Session Report")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    if export.isLive {
                        Text("Session started \(shortTime(export.sessionStart)) · \(TimeInterval(export.generatedAt.timeIntervalSince(export.sessionStart)).durationHM) in progress")
                            .font(.system(size: 12.5))
                            .foregroundStyle(ink2)
                    } else {
                        Text(export.sessionStart, format: .dateTime.weekday(.wide).month().day().year())
                            .font(.system(size: 12.5))
                            .foregroundStyle(ink2)
                    }
                }
                Spacer()
                if export.isLive {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Generated")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ink2)
                        Text(export.generatedAt, format: .dateTime.year().month().day().hour().minute())
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ink2)
                    }
                }
            }
            Rectangle().fill(ink).frame(height: 2)
        }
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.system(size: 12, weight: .bold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(Theme.accent)
            Rectangle().fill(hair).frame(height: 1)
        }
        .padding(.top, 26)
        .padding(.bottom, 14)
    }

    // MARK: Notes

    private func noteRow(_ note: SessionStateExport.NoteLine) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: TripReport.tPlus(note.timestamp.timeIntervalSince(export.sessionStart)))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text(verbatim: shortTime(note.timestamp))
                    .font(.system(size: 10.5))
                    .foregroundStyle(ink2)
            }
            .frame(width: 64, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                if !note.structure.isEmpty || note.kind == .checkIn {
                    HStack(spacing: 6) {
                        if note.kind == .checkIn {
                            Text("Check-in").font(.system(size: 10, weight: .semibold)).foregroundStyle(ink2)
                        }
                        if !note.structure.isEmpty {
                            Text(verbatim: note.structure).font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        }
                    }
                }
                if !note.text.isEmpty {
                    Text(verbatim: note.text).font(.system(size: 12.5))
                }
                if !note.descriptors.isEmpty {
                    Text(verbatim: note.descriptors.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    // MARK: Interaction

    private func interactionCallout(_ line: SessionStateExport.InteractionLine) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(line.severity.exportSymbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(line.severity.exportLabel): \(line.a) + \(line.b)")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(line.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(hex: "FBF0E4"))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "F0D9B8"), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(Color(hex: "7C5210"))
    }

    // MARK: Subjective

    private func subjectiveRow(_ s: SessionStateExport.SubstanceState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.name).font(.system(size: 15, weight: .bold))
                Text("\(s.amount.doseFormatted) \(s.unit) · \(s.route)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(ink2)
                Spacer()
                if export.isLive {
                    Text(s.phase.displayName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(s.phase.color, in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Text(shortTime(s.doseTimestamp))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(ink2)
                }
            }
            if export.isLive {
                HStack(spacing: 16) {
                    metric(String(localized: "Taken"), "\(shortTime(s.doseTimestamp)) · \(TimeInterval(export.generatedAt.timeIntervalSince(s.doseTimestamp)).durationHM) ago")
                    metric(String(localized: "Intensity"), "\(Int((s.intensity * 100).rounded()))% of peak")
                    metric(String(localized: "Next"), nextText(s))
                }
            }
            PhaseTimelineBar(state: s, showNow: export.isLive).frame(height: 30)
        }
        .padding(.vertical, 14)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        Text("\(Text(label).foregroundStyle(ink2)) \(Text(value).fontWeight(.semibold))")
            .font(.system(size: 12))
            .monospacedDigit()
    }

    private func nextText(_ s: SessionStateExport.SubstanceState) -> String {
        if let next = s.next {
            return "\(next.phase.displayName.lowercased()) ~\(next.at.timeIntervalSince(export.generatedAt).durationHM)"
        }
        return "\(String(localized: "baseline")) \(shortTime(s.baselineAt))"
    }

    private var phaseLegend: some View {
        HStack(spacing: 13) {
            ForEach(SessionStateExport.Phase.allCases, id: \.self) { phase in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(phase.color).frame(width: 8, height: 8)
                    Text(phase.displayName).font(.system(size: 10.5)).foregroundStyle(ink2)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Elimination

    private func eliminationCard(_ group: SessionStateExport.EliminationGroup) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(group.name).font(.system(size: 14, weight: .bold))
                    if group.doseCount > 1 {
                        Text(verbatim: "×\(group.doseCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ink2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(hair.opacity(0.6), in: Capsule())
                    }
                    Spacer()
                    Text(halfLifeLabel(group)).font(.system(size: 11, design: .monospaced)).foregroundStyle(ink2)
                }
                if export.isLive { inBodyNow(group) }
                VStack(spacing: 3) {
                    ForEach(milestones(group), id: \.0) { label, value in
                        HStack {
                            Text(label).font(.system(size: 11.5)).foregroundStyle(ink2)
                            Spacer()
                            Text(value).font(.system(size: 11.5, design: .monospaced))
                        }
                    }
                }
            }
            if !group.curve.isEmpty {
                EliminationCurveView(samples: group.curve, nowFraction: export.isLive ? nowFraction(group) : nil, accent: Theme.accent, ink2: ink2)
                    .frame(width: 210, height: 96)
            }
        }
        .padding(14)
        .background(panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(hair, lineWidth: 1))
    }

    private func nowFraction(_ group: SessionStateExport.EliminationGroup) -> Double {
        guard group.horizonMinutes > 0 else { return 0 }
        let elapsed = export.generatedAt.timeIntervalSince(group.groupStart) / 60
        return min(1, max(0, elapsed / group.horizonMinutes))
    }

    @ViewBuilder
    private func inBodyNow(_ group: SessionStateExport.EliminationGroup) -> some View {
        switch group.model {
        case let .firstOrder(_, remaining, fraction, _, _, _):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(fmt(remaining, group.unit)).font(.system(size: 16, weight: .bold, design: .monospaced))
                Text("in body").font(.system(size: 12)).foregroundStyle(ink2)
                Text("\(Text(verbatim: "· \(Int(((1 - fraction) * 100).rounded()))%")) \(Text("gone"))")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent)
            }
        case let .zeroOrder(grams, _, _, _, _):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(fmt(grams, "g")).font(.system(size: 16, weight: .bold, design: .monospaced))
                Text("left in body").font(.system(size: 12)).foregroundStyle(ink2)
            }
        case .unknown:
            Text("No half-life data — elimination not modeled")
                .font(.system(size: 12)).foregroundStyle(ink2)
        }
    }

    private func fmt(_ v: Double, _ unit: String) -> String {
        let s = v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
        return "\(s) \(unit)"
    }

    private func halfLifeLabel(_ group: SessionStateExport.EliminationGroup) -> String {
        switch group.model {
        case let .firstOrder(hl, _, _, _, _, _): "t½ \(TimeInterval(hl * 60).durationHM)"
        case .zeroOrder: String(localized: "zero-order")
        case .unknown: "—"
        }
    }

    private func milestones(_ group: SessionStateExport.EliminationGroup) -> [(String, String)] {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        func clock(_ d: Date) -> String {
            f.string(from: d)
        }
        switch group.model {
        case let .firstOrder(_, _, _, t50, t90, cleared):
            return [
                (String(localized: "50% eliminated"), clock(t50)),
                (String(localized: "90% eliminated"), clock(t90)),
                (String(localized: "Effectively clear"), clock(cleared)),
            ]
        case let .zeroOrder(_, _, t50, t90, sober):
            return [
                (String(localized: "50% eliminated"), clock(t50)),
                (String(localized: "90% eliminated"), clock(t90)),
                (String(localized: "Sober"), clock(sober)),
            ]
        case .unknown:
            return []
        }
    }

    // MARK: Footer

    private var footer: some View {
        Text("Model estimates (one-compartment oral PK; alcohol zero-order) from population half-lives and your logged doses — individual clearance varies. Subjective intensity is relative to each dose's own peak. Not medical advice.")
            .font(.system(size: 10.5))
            .foregroundStyle(ink2)
            .padding(.top, 26)
            .overlay(alignment: .top) { Rectangle().fill(hair).frame(height: 1) }
            .padding(.top, 4)
    }
}

// MARK: - Charts

private struct PhaseTimelineBar: View {
    let state: SessionStateExport.SubstanceState
    /// The vertical "now" progression marker — drawn only for a live session.
    var showNow: Bool = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let barY = h - 8
            ZStack(alignment: .topLeading) {
                // Phase segments.
                ForEach(Array(segments().enumerated()), id: \.offset) { _, seg in
                    seg.color
                        .frame(width: max(0, (seg.end - seg.start) * w), height: 8)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                        .offset(x: seg.start * w, y: barY)
                }
                // Intensity curve.
                intensityPath(width: w, height: barY - 2)
                    .stroke(Color(hex: "201519").opacity(0.35), lineWidth: 0.8)
                // Now marker (live only).
                if showNow {
                    Rectangle()
                        .fill(state.phase.color)
                        .frame(width: 1.2, height: h)
                        .offset(x: state.progress * w)
                }
            }
        }
    }

    private struct Seg { let start: Double; let end: Double; let color: Color }

    private func segments() -> [Seg] {
        let b = state.phaseBoundaries + [1.0] // onsetEnd, comeupEnd, peakEnd, offsetEnd, 1
        let colors = SessionStateExport.Phase.allCases.map(\.color)
        var segs: [Seg] = []
        var start = 0.0
        for i in 0 ..< min(b.count, colors.count) {
            let end = max(start, b[i])
            segs.append(Seg(start: start, end: end, color: colors[i]))
            start = end
        }
        return segs
    }

    private func intensityPath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            let samples = state.effectCurve
            guard samples.count > 1 else { return }
            for (i, v) in samples.enumerated() {
                let x = CGFloat(i) / CGFloat(samples.count - 1) * width
                let y = height - CGFloat(v) * height
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }
}

private struct EliminationCurveView: View {
    let samples: [Double]
    /// `nil` for a historical session — no "now" marker/dot is drawn.
    let nowFraction: Double?
    let accent: Color
    let ink2: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let padTop: CGFloat = 8
            let padBottom: CGFloat = 12
            let plotH = h - padTop - padBottom
            let peak = max(samples.max() ?? 1, 1e-9)
            let count = CGFloat(max(samples.count - 1, 1))

            ZStack(alignment: .topLeading) {
                // Filled area.
                Path { p in
                    guard samples.count > 1 else { return }
                    p.move(to: CGPoint(x: 0, y: padTop + plotH))
                    for i in samples.indices {
                        p.addLine(to: CGPoint(x: CGFloat(i) / count * w, y: padTop + (1 - CGFloat(samples[i] / peak)) * plotH))
                    }
                    p.addLine(to: CGPoint(x: w, y: padTop + plotH))
                    p.closeSubpath()
                }
                .fill(accent.opacity(0.12))
                // Line.
                Path { p in
                    guard samples.count > 1 else { return }
                    for i in samples.indices {
                        let pt = CGPoint(x: CGFloat(i) / count * w, y: padTop + (1 - CGFloat(samples[i] / peak)) * plotH)
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(accent, lineWidth: 1.6)
                // Now marker + dot (live sessions only).
                if let nowFraction {
                    let nowX = CGFloat(nowFraction) * w
                    let nowIdx = min(samples.count - 1, max(0, Int((nowFraction * Double(max(samples.count - 1, 1))).rounded())))
                    let nowY = padTop + (1 - CGFloat(samples[nowIdx] / peak)) * plotH
                    Rectangle().fill(ink2.opacity(0.5)).frame(width: 0.8, height: plotH).offset(x: nowX, y: padTop)
                    Circle().fill(accent).frame(width: 5, height: 5).offset(x: nowX - 2.5, y: nowY - 2.5)
                }
            }
        }
    }
}

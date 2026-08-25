import SwiftUI

/// Apple Health step. Health gives Piru two things at once, so this screen is framed around the
/// connection rather than the number: your **body weight** is the denominator that turns a dose
/// into an exposure (so estimates fit your body), and your **heart rate / blood pressure** overlay
/// on each session turns a modeled curve into a record of what your body actually did. A small
/// illustrative chart previews that overlay — an alcohol curve (both body-weight dependent and a
/// reliable heart-rate raiser) with the heart rate a watch recorded beneath it.
///
/// "Continue" is the connect action: it surfaces a single Health sheet covering weight, heart rate,
/// and blood pressure, opts the session-vitals overlay on, and reads the latest weight. The weight
/// stepper stays as a manual control — whatever it shows is saved, so a user who declines Health
/// still keeps their weight. "I'll set this later" skips the whole thing.
struct OnboardingHealthStep: View {
    @Environment(\.onboardingNav) private var nav
    @State private var health = HealthKitBodyMass.shared
    /// Connecting Health here opts the user into the session heart-rate /
    /// blood-pressure overlay (they see it in the same sheet); still off-able in
    /// Settings. Stored in the app-group suite so the whole app agrees.
    @AppStorage("showSessionVitals", store: UserDefaults(suiteName: "group.dev.yumeji.piru"))
    private var showSessionVitals = false

    @State private var weightKg: Double = UserProfileStore.shared.weightKg ?? UserProfileStore.defaultWeightKg
    /// The kilograms Apple Health returned, if any — so an unchanged Health value keeps its
    /// provenance (launch auto-sync) while a nudged value becomes a manual entry.
    @State private var healthValue: Double?
    @State private var connecting = false
    @State private var noReadNote = false

    var body: some View {
        OnboardingLayout(
            title: "Connect Apple Health",
            subtitle: "Your body weight sizes every estimate to you — and your heart rate shows how your body actually answered each dose, right on the session timeline.",
        ) {
            OnboardingIconHero(symbol: "heart.text.square.fill")
        } mid: {
            VStack(spacing: 16) {
                OnboardingVitalsSampleChart()

                VStack(spacing: 8) {
                    HStack {
                        Text("Your body weight")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    InventoryStepperRow(value: $weightKg, unit: "kg", label: "Your body weight", stepBasis: 10)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .themeCapsule()
                    noteView
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
        } footer: {
            GlassPillButton(title: connecting ? "Connecting…" : "Continue") {
                Task { await connectAndAdvance() }
            }
            GlassPillButton(title: "I'll Set This Later", prominence: .neutral, action: nav.advance)
        }
    }

    private var noteView: some View {
        Group {
            if healthValue != nil {
                Label("Synced from Apple Health — check the number looks right.", systemImage: "checkmark.circle")
            } else if noReadNote {
                Label("Couldn't read a weight from Health. Set it above instead.", systemImage: "exclamationmark.circle")
            } else {
                Label("Health access is read-only. Turn it off anytime in Settings.", systemImage: "lock.shield")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondaryLabel)
        // Without this the note truncated to "…Turn it off anytime in S…" when
        // the step ran tall — same mechanism as the title above it.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Continue connects Health, then advances. One Health sheet covers weight + heart rate +
    /// blood pressure; connecting opts into the session vitals overlay (off-able in Settings).
    /// Whatever weight the stepper shows is saved either way, so declining Health still keeps it.
    private func connectAndAdvance() async {
        guard !connecting else { return }
        connecting = true
        noReadNote = false
        await HealthKitVitals.shared.requestFullAccess()
        showSessionVitals = true
        let result = await health.syncLatest()
        connecting = false
        switch result {
        case let .updated(kg):
            healthValue = kg
            weightKg = kg
        case .noData, .unavailable:
            noReadNote = true
        }
        save()
        nav.advance()
    }

    private func save() {
        let range = UserProfileStore.weightRangeKg
        let kg = min(range.upperBound, max(range.lowerBound, weightKg))
        // Compare against the clamped Health value: an out-of-range Health read
        // clamps to the same bound the user's value did, and still counts as
        // HealthKit provenance rather than a manual entry.
        let clampedHealth = healthValue.map { min(range.upperBound, max(range.lowerBound, $0)) }
        if let clampedHealth, abs(clampedHealth - kg) < 0.05 {
            UserProfileStore.shared.setHealthKitWeight(kg)
        } else {
            UserProfileStore.shared.setManualWeight(kg)
        }
    }
}

/// A static, illustrative preview of the session vitals overlay: an alcohol effect curve with the
/// heart rate a watch recorded alongside it in the companion band beneath — the same shape a real
/// session shows, so the value of connecting Health is legible before the user decides. Alcohol is
/// the example because it's both body-weight dependent (weight matters) and a reliable HR raiser.
/// Fully synthetic and deterministic; nothing here reads Health.
private struct OnboardingVitalsSampleChart: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                legend(color: Theme.accent, label: "Alcohol")
                legend(color: VitalsPalette.heart, label: "Heart rate")
                Spacer()
            }
            Canvas { context, size in draw(in: &context, size: size) }
                .frame(height: 108)
            Text("A couple of drinks, with the heart rate a watch recorded alongside.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .themeCard(cornerRadius: 22)
        .accessibilityElement()
        .accessibilityLabel("Example chart: an alcohol effect curve with heart rate rising and falling alongside it.")
    }

    private func legend(color: Color, label: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.secondaryLabel)
        }
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let pad: CGFloat = 4
        let plotW = size.width - pad * 2
        let gap: CGFloat = 8
        let bandH = size.height * 0.34
        let effectTop: CGFloat = 4
        let effectBottom = size.height - bandH - gap
        let effectH = effectBottom - effectTop
        let bandTop = effectBottom + gap
        let bandBottom = size.height

        let count = 80
        func frac(_ i: Int) -> Double {
            Double(i) / Double(count - 1)
        }
        func px(_ i: Int) -> CGFloat {
            pad + CGFloat(frac(i)) * plotW
        }

        /// Alcohol effect — a Bateman bump over ~4 h, normalized to a peak of 1.
        func rawEffect(_ t: Double) -> Double {
            let minutes = t * 240
            return exp(-0.017 * minutes) - exp(-0.055 * minutes)
        }
        let peak = stride(from: 0.0, through: 1.0, by: 0.01).map(rawEffect).max() ?? 1
        func effect(_ t: Double) -> Double {
            max(0, rawEffect(t) / peak)
        }

        // Filled effect area + line.
        var area = Path()
        area.move(to: CGPoint(x: pad, y: effectBottom))
        for i in 0 ..< count {
            area.addLine(to: CGPoint(x: px(i), y: effectBottom - CGFloat(effect(frac(i))) * effectH))
        }
        area.addLine(to: CGPoint(x: pad + plotW, y: effectBottom))
        area.closeSubpath()
        context.fill(area, with: .linearGradient(
            Gradient(colors: [Theme.accent.opacity(0.34), Theme.accent.opacity(0.03)]),
            startPoint: CGPoint(x: 0, y: effectTop),
            endPoint: CGPoint(x: 0, y: effectBottom),
        ))
        var curve = Path()
        for i in 0 ..< count {
            let point = CGPoint(x: px(i), y: effectBottom - CGFloat(effect(frac(i))) * effectH)
            if i == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
        }
        context.stroke(curve, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // Dose dot at t=0, rimmed in the background color so it reads against the fill.
        let dose = CGRect(x: pad - 3.5, y: effectBottom - 3.5, width: 7, height: 7)
        context.fill(Path(ellipseIn: dose), with: .color(Theme.accent))
        context.stroke(Path(ellipseIn: dose), with: .color(Theme.background), lineWidth: 1.5)

        // Companion cardio band — a faint crimson lane, echoing the real overlay.
        let band = CGRect(x: pad, y: bandTop, width: plotW, height: bandH)
        context.fill(Path(roundedRect: band, cornerRadius: 8), with: .color(VitalsPalette.heart.opacity(0.07)))

        // Heart rate — baseline + a lagged, gently jittered echo of the effect.
        let hrLo = 58.0, hrHi = 92.0
        func hr(_ t: Double) -> Double {
            62 + 26 * effect(max(0, t - 0.06)) + 2.2 * sin(t * 20)
        }
        func yHR(_ bpm: Double) -> CGFloat {
            let clamped = min(hrHi, max(hrLo, bpm))
            return bandBottom - 4 - CGFloat((clamped - hrLo) / (hrHi - hrLo)) * (bandH - 8)
        }
        var hrArea = Path()
        hrArea.move(to: CGPoint(x: pad, y: bandBottom - 4))
        for i in 0 ..< count {
            hrArea.addLine(to: CGPoint(x: px(i), y: yHR(hr(frac(i)))))
        }
        hrArea.addLine(to: CGPoint(x: pad + plotW, y: bandBottom - 4))
        hrArea.closeSubpath()
        context.fill(hrArea, with: .color(VitalsPalette.heart.opacity(0.12)))
        var hrLine = Path()
        for i in 0 ..< count {
            let point = CGPoint(x: px(i), y: yHR(hr(frac(i))))
            if i == 0 { hrLine.move(to: point) } else { hrLine.addLine(to: point) }
        }
        context.stroke(hrLine, with: .color(VitalsPalette.heart), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        let now = CGPoint(x: px(count - 1), y: yHR(hr(frac(count - 1))))
        context.fill(Path(ellipseIn: CGRect(x: now.x - 3, y: now.y - 3, width: 6, height: 6)), with: .color(VitalsPalette.heart))
    }
}

#Preview {
    OnboardingHealthStep()
        .background(Theme.background)
}

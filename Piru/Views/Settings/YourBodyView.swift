import SwiftUI

/// Settings ▸ Your Body: the facts about the user's body that Piru's estimates
/// are sized to — weight and the metabolism flags. Every row says what the app
/// does with the fact, and the weight row says where its number came from.
struct YourBodyView: View {
    @State private var profileStore = UserProfileStore.shared
    /// Whether the Health prompt has never been shown for weight. Nil until the
    /// async status check resolves, so the caption doesn't flicker between states.
    @State private var healthNeverAsked: Bool?

    var body: some View {
        List {
            Group {
                Section {
                    BodyWeightRow(
                        weightKg: profileStore.weightKg,
                        source: profileStore.weightSource,
                        healthAccess: healthAccess,
                    )
                }

                Section {
                    GrapefruitRow(isOn: grapefruitBinding)
                    AlcoholFlushRow(isOn: aldh2Binding)
                } header: {
                    Text("Metabolism")
                }
            }
            .listRowBackground(CardBackground())
        }
        .themedPage()
        .navigationTitle("Your Body")
        .inlineNavigationTitle()
        .task { healthNeverAsked = await HealthKitBodyMass.shared.accessWasNeverRequested() }
    }

    private var healthAccess: BodyWeightRow.HealthAccess {
        guard HealthKitBodyMass.shared.isAvailable else { return .unavailable }
        switch healthNeverAsked {
        case true: return .neverAsked
        case false: return .asked
        case nil: return .unresolved
        }
    }

    // MARK: - Bindings

    private var grapefruitBinding: Binding<Bool> {
        Binding(
            get: { profileStore.grapefruitLoggingEnabled },
            set: { profileStore.setGrapefruitLoggingEnabled($0) },
        )
    }

    private var aldh2Binding: Binding<Bool> {
        Binding(
            get: { profileStore.aldh2Deficient },
            set: { profileStore.setALDH2Deficient($0) },
        )
    }
}

// MARK: - Weight

/// The weight every estimate is sized to, with its provenance, and a push to the
/// Apple Health screen where it is edited and where Health access is granted.
private struct BodyWeightRow: View {
    /// What the app can honestly say about Health access for weight. iOS hides
    /// whether a read was granted, but it does say whether it was ever asked.
    enum HealthAccess {
        case neverAsked
        case asked
        case unavailable
        case unresolved
    }

    let weightKg: Double?
    let source: UserProfileStore.WeightSource
    let healthAccess: HealthAccess

    var body: some View {
        NavigationLink {
            HealthSettingsView()
        } label: {
            HStack(spacing: Spacing.md) {
                CaptionedRowLabel(title: "Your body weight", systemImage: "scalemass", caption: Text(caption))
                Spacer(minLength: 0)
                Text(verbatim: "\(effectiveWeightKg.doseFormatted) kg")
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryLabel)
            }
        }
    }

    private var effectiveWeightKg: Double {
        weightKg ?? UserProfileStore.defaultWeightKg
    }

    private var caption: LocalizedStringResource {
        switch source {
        case .healthKit:
            "Synced from Apple Health. Your weight sizes every dose estimate — the same dose hits harder the less you weigh."
        case .manual:
            "Entered manually. Your weight sizes every dose estimate — the same dose hits harder the less you weigh."
        case .estimated:
            estimatedCaption
        }
    }

    private var estimatedCaption: LocalizedStringResource {
        switch healthAccess {
        case .neverAsked:
            "Using the average 60 kg. Apple Health has never been connected on this device — connect it, or set your weight, so estimates fit your body."
        case .asked:
            "Using the average 60 kg. Health returned no weight — check Settings ▸ Privacy & Security ▸ Health ▸ Piru, or set yours by hand."
        case .unavailable, .unresolved:
            "Using the average 60 kg. Set yours so estimates fit your body — the same dose hits harder the less you weigh."
        }
    }
}

// MARK: - Metabolism

private struct GrapefruitRow: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            CaptionedRowLabel(
                title: "Grapefruit dose logging",
                systemImage: "carrot",
                caption: Text("Adds a per-dose grapefruit toggle for substances whose breakdown grapefruit slows (CYP3A4), so the entry records it."),
            )
        }
        .tint(Theme.accent)
    }
}

private struct AlcoholFlushRow: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            CaptionedRowLabel(
                title: "I get the alcohol flush",
                systemImage: "wineglass",
                caption: Text("Shows the acetaldehyde build-up on alcohol entries — the flush is the ALDH2 variant that lets it accumulate."),
            )
        }
        .tint(Theme.accent)
    }
}

#Preview {
    NavigationStack { YourBodyView() }
}

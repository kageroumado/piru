/// Where the app records that the user finished onboarding.
enum OnboardingState {
    /// The `UserDefaults` key, `true` once onboarding is done. Exported and
    /// restored with the other settings, so the spelling is part of the backup
    /// format.
    nonisolated static let completedKey = "hasCompletedOnboarding"
}

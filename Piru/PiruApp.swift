import BackgroundTasks
import SwiftData
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif
import UserNotifications
import WidgetKit

// A UIKit background-execution assertion that ends itself exactly once —
// explicitly via ``end()`` when the protected work finishes, or from the
// system's expiration handler if time runs out first.
#if canImport(UIKit)
    @MainActor
    private final class BackgroundTaskAssertion {
        private var id: UIBackgroundTaskIdentifier = .invalid

        init(name: String) {
            id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
                self?.end()
            }
        }

        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }
#endif

// MARK: - App

/// The iOS and macOS host. The launch and lifecycle policy is ``AppLaunch``,
/// shared with the Android host; this type adds what only Apple platforms have.
@main
struct PiruApp: App {
    let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Settings ▸ Language, before anything looks up a string.
        AppLanguageModel.applyAtLaunch()

        // Release every GRDB lock when the app is backgrounded, before the first
        // connection opens (the store probe in `openStore` is one): a lock held
        // into suspension is a 0xdead10cc kill. See DatabaseSuspension.
        DatabaseSuspension.install()

        // Opening the store reads, and on an update migrates, the App Group
        // SQLite file, and `init` also runs for prewarmed and background
        // launches, which iOS may suspend at any point. A suspension while
        // SQLite holds a lock there is a 0xdead10cc kill, so ask for the
        // process to stay up until the store is open. See BackgroundActivity.
        let storeOpening = BackgroundActivity.hold("Open journal store")

        // A successor install's first launch brings the legacy app's journal and
        // settings across before anything opens the store; the legacy build
        // publishes what only its sandbox can see for that successor to read.
        LegacyHandoff.importIfSuccessor()
        Self.publishLegacyHandoff()

        container = AppLaunch.openStore()
        storeOpening.end()
        // The Log Dose action saves with no view hierarchy; App Intents launch
        // the app before performing, so this is set before any `perform()`.
        DoseIntentLogger.modelContainer = container
        AppLanguageModel.shared.modelContainer = container

        // Reads what this person owns and starts listening for purchases that
        // land outside a purchase call (Ask to Buy, refunds, another device).
        SkinShop.shared.start()

        // Routes notification taps (routine reminders carry a piru:// deep
        // link). The center holds its delegate weakly — the shared instance
        // keeps it alive.
        UNUserNotificationCenter.current().delegate = DoseNotificationDelegate.shared

        // Activate the Apple Watch sync: push the favorites/recents manifest to the wrist
        // and receive watch-logged doses through the canonical insert path. No-op where
        // WatchConnectivity is unsupported (iPad, Mac). See Specs/apple-watch-companion.md.
        #if os(iOS)
            PhoneSyncCoordinator.shared.configure(container: container)
        #endif

        #if os(iOS)
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: LiveActivityManager.backgroundTaskIdentifier,
                using: .main,
            ) { task in
                guard let task = task as? BGAppRefreshTask else { return }
                LiveActivityManager.shared.handleBackgroundRefresh(task)
            }
        #endif
    }

    #if DEBUG
        private static let forcesDifferentiateWithoutColor =
            ProcessInfo.processInfo.arguments.contains("-piruDifferentiateWithoutColor")
    #endif

    var body: some Scene {
        WindowGroup {
            SkinnedRoot {
                if AppIdentity.isLegacy {
                    AppMovedView()
                } else {
                    root
                }
            }
            #if DEBUG && os(iOS)
            .statusBarHidden(ScreenshotTour.wantsWallpapers)
            #endif
            .task {
                guard !AppIdentity.isLegacy else { return }
                WidgetCenter.shared.reloadAllTimelines()
                await AppLaunch.finishLaunching(container: container, hooks: Self.launchHooks)
            }
        }
        .modelContainer(container)
        #if os(macOS)
            // Room for the sidebar, a journal column and the Log sheet over it.
            .defaultSize(width: 1100, height: 760)
        #endif
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, !AppIdentity.isLegacy {
                    AppLaunch.becameActive(container: container)
                }
                if phase == .background {
                    enterBackground()
                }
            }
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
            if ScreenshotTour.wantsWallpapers {
                ScreenshotTour.WallpaperCanvas()
            } else {
                // `-piruDifferentiateWithoutColor` turns the setting on
                // for this launch: the simulator's Accessibility
                // preference can't be set from simctl.
                ContentView()
                    .transformEnvironment(\._accessibilityDifferentiateWithoutColor) { value in
                        if Self.forcesDifferentiateWithoutColor { value = true }
                    }
            }
        #else
            ContentView()
        #endif
    }

    /// TipKit and HealthKit work at the launch task's fixed points.
    private static var launchHooks: AppLaunch.Hooks {
        AppLaunch.Hooks(
            engagementKnown: { hasLoggedDose in
                // First-run contextual tips (gated on onboarding completion),
                // then the tips ladder (log a dose → where settings live).
                OnboardingTips.configure()
                OnboardingTips.updateEngagement(hasLoggedDose: hasLoggedDose)
            },
            passesFinished: {
                // If the user connected Apple Health for body weight, silently refresh it
                // (no prompt). On a revoked/empty read we deliberately KEEP the last-known weight
                // rather than clear it — a slightly stale real weight beats reverting to the 60 kg
                // population default. The Body Weight screen surfaces the empty-read state so the
                // user can re-grant access or update it.
                if UserProfileStore.shared.weightSource == .healthKit {
                    Task { await HealthKitBodyMass.shared.syncLatest() }
                }
            },
        )
    }

    private func enterBackground() {
        // Tear down any live keyboard before suspension. Suspending with
        // a first responder up can strand UIKit's scene-level keyboard
        // state, and every sheet presented after foregrounding then lays
        // out keyboard-avoiding — the QuickLog dock floats one keyboard
        // height above the bottom with a dead touch zone below it
        // (TestFlight feedback on build 2.2 (30), iOS 26.5.2).
        #if canImport(UIKit)
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil,
            )
        #endif
        Self.publishLegacyHandoff(backgrounding: true)
        // Hold a background-execution assertion across the await so
        // iOS can't suspend the process mid-write; ended on completion
        // or expiration, whichever comes first.
        #if canImport(UIKit)
            let assertion = BackgroundTaskAssertion(name: "AutomaticBackup")
            Task {
                defer { assertion.end() }
                await AppLaunch.enteredBackground(container: container)
            }
        #else
            Task {
                await AppLaunch.enteredBackground(container: container)
            }
        #endif
    }

    /// Publish the legacy build's handoff off the main thread. On backgrounding
    /// it holds a background-execution assertion so the publish finishes before
    /// the process is suspended; at launch, from `init`, there is no
    /// `UIApplication` to ask yet. Returns at once in the successor.
    private static func publishLegacyHandoff(backgrounding: Bool = false) {
        guard AppIdentity.isLegacy else { return }
        #if canImport(UIKit)
            let assertion = backgrounding ? BackgroundTaskAssertion(name: "LegacyHandoff") : nil
            Task.detached(name: "Publish legacy handoff", priority: .utility) {
                LegacyHandoff.publishIfLegacy()
                await assertion?.end()
            }
        #else
            Task.detached(name: "Publish legacy handoff", priority: .utility) {
                LegacyHandoff.publishIfLegacy()
            }
        #endif
    }
}

import Foundation

/// Sprint 24: the tutorial's state is a device setting in UserDefaults, under the `Tutorial` namespace. It is not app
/// data: it is not in SwiftData or backups.
enum TutorialSettings {
    /// The tour has started on this device (on its own, from the offer, or from Settings).
    static let tourSeenKey = "Tutorial.tourSeen"
    /// The Dashboard's one-time offer was answered, Start or Not now.
    static let offerAnsweredKey = "Tutorial.offerAnswered"

    /// UI tests start from a device that has never seen the tour; `-uiTestingTour` decides whether it may appear.
    static func resetForUITesting(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: tourSeenKey)
        defaults.removeObject(forKey: offerAnsweredKey)
    }
}

/// When the first-run tour starts on its own, and when the Dashboard offers it. Pure, so it is unit-tested.
struct TourLaunchPolicy: Equatable, Sendable {
    /// Launched for UI tests (`-uiTesting`).
    var isUITesting: Bool
    /// A UI test about the tour (`-uiTestingTour`); without it the tour and the offer never appear under UI tests.
    var allowsTourInUITests: Bool
    var tourSeen: Bool
    var offerAnswered: Bool

    /// Whether the tour or its offer may appear without being asked for from Settings.
    var mayAppearOnItsOwn: Bool { !isUITesting || allowsTourInUITests }

    /// A fresh install: the tour starts once, right after onboarding completes.
    var startsAfterOnboarding: Bool { mayAppearOnItsOwn && !tourSeen }

    /// An install whose setup was done before the tour existed: a one-time offer on the Dashboard, gone for good once
    /// answered or once the tour has run. A fresh install finishes onboarding after launch, so it never sees it.
    func offersTour(onboardingCompletedAtLaunch: Bool) -> Bool {
        mayAppearOnItsOwn && onboardingCompletedAtLaunch && !tourSeen && !offerAnswered
    }

    static func current(arguments: [String], defaults: UserDefaults) -> TourLaunchPolicy {
        TourLaunchPolicy(
            isUITesting: arguments.contains(LaunchArguments.uiTesting),
            allowsTourInUITests: arguments.contains(LaunchArguments.tourTesting),
            tourSeen: defaults.bool(forKey: TutorialSettings.tourSeenKey),
            offerAnswered: defaults.bool(forKey: TutorialSettings.offerAnsweredKey))
    }
}

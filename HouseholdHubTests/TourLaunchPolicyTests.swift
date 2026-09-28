import Foundation
import Testing

@testable import HouseholdHub

/// Sprint 24: when the first-run tour starts on its own and when the Dashboard offers it.
struct TourLaunchPolicyTests {
    private static func policy(
        uiTesting: Bool = false, tourTesting: Bool = false, seen: Bool = false, answered: Bool = false
    ) -> TourLaunchPolicy {
        TourLaunchPolicy(
            isUITesting: uiTesting, allowsTourInUITests: tourTesting, tourSeen: seen, offerAnswered: answered)
    }

    /// A case for the offer: the state at launch and whether the Dashboard shows it.
    struct OfferCase: Sendable, CustomTestStringConvertible {
        let onboarded: Bool
        let seen: Bool
        let answered: Bool
        let offers: Bool

        var testDescription: String { "onboarded \(onboarded), seen \(seen), answered \(answered)" }
    }

    static let offerCases: [OfferCase] = [
        // An install set up before the tour existed: offered once.
        OfferCase(onboarded: true, seen: false, answered: false, offers: true),
        // Start or Not now answered it.
        OfferCase(onboarded: true, seen: false, answered: true, offers: false),
        // The tour already ran (after onboarding, or from Settings).
        OfferCase(onboarded: true, seen: true, answered: false, offers: false),
        OfferCase(onboarded: true, seen: true, answered: true, offers: false),
        // A fresh install: onboarding comes first, then the tour itself.
        OfferCase(onboarded: false, seen: false, answered: false, offers: false),
    ]

    @Test(arguments: offerCases)
    func offerIsShownOnceToSetUpInstalls(_ entry: OfferCase) {
        let policy = Self.policy(seen: entry.seen, answered: entry.answered)
        #expect(policy.offersTour(onboardingCompletedAtLaunch: entry.onboarded) == entry.offers)
    }

    @Test func freshInstallStartsTheTourAfterOnboardingOnce() {
        #expect(Self.policy().startsAfterOnboarding)
        #expect(!Self.policy(seen: true).startsAfterOnboarding)
    }

    /// The 78 other UI tests depend on this: under `-uiTesting` nothing appears unless `-uiTestingTour` is passed.
    @Test(arguments: [false, true])
    func uiTestsSeeTheTourOnlyWhenAskedFor(_ tourTesting: Bool) {
        let policy = Self.policy(uiTesting: true, tourTesting: tourTesting)
        #expect(policy.mayAppearOnItsOwn == tourTesting)
        #expect(policy.startsAfterOnboarding == tourTesting)
        #expect(policy.offersTour(onboardingCompletedAtLaunch: true) == tourTesting)
    }

    @Test func tourArgumentAloneChangesNothingOutsideUITests() {
        let policy = Self.policy(tourTesting: true)
        #expect(policy.mayAppearOnItsOwn)
        #expect(policy.offersTour(onboardingCompletedAtLaunch: true))
    }

    @Test func currentReadsArgumentsAndTheTutorialKeys() throws {
        let suite = "TourLaunchPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let fresh = TourLaunchPolicy.current(arguments: ["app"], defaults: defaults)
        #expect(fresh == Self.policy())

        defaults.set(true, forKey: TutorialSettings.tourSeenKey)
        defaults.set(true, forKey: TutorialSettings.offerAnsweredKey)
        let arguments = ["app", LaunchArguments.uiTesting, LaunchArguments.tourTesting]
        let stored = TourLaunchPolicy.current(arguments: arguments, defaults: defaults)
        #expect(stored == Self.policy(uiTesting: true, tourTesting: true, seen: true, answered: true))
    }

    @Test func keysLiveUnderTheTutorialNamespace() {
        #expect(TutorialSettings.tourSeenKey.hasPrefix("Tutorial."))
        #expect(TutorialSettings.offerAnsweredKey.hasPrefix("Tutorial."))
    }

    @Test func uiTestingResetForgetsTheTour() throws {
        let suite = "TourLaunchPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: TutorialSettings.tourSeenKey)
        defaults.set(true, forKey: TutorialSettings.offerAnsweredKey)

        TutorialSettings.resetForUITesting(defaults)

        #expect(TourLaunchPolicy.current(arguments: [], defaults: defaults) == Self.policy())
    }

    @Test func theTourHasSixStopsEachWithItsOwnTarget() {
        #expect(TourStep.all.count == 6)
        #expect(Set(TourStep.all.map(\.target)).count == 6)
        #expect(TourStep.all.map(\.screen) == [.dashboard, .dashboard, .budget, .wishlist, .tasks, .more])
    }
}

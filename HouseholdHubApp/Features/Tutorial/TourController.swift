import CoreGraphics
import Foundation
import Observation

/// Sprint 24: the first-run tour's state. One for the app's single window, like `AppRouter`, which it drives to open
/// each stop's tab. Targets report their frames here (`.tourTarget(_:)`); `TourOverlay` draws the spotlight.
@MainActor
@Observable
final class TourController {
    static let shared = TourController(router: .shared)

    /// The stop showing, as an index into `TourStep.all`; nil while no tour runs.
    private(set) var stepIndex: Int?
    /// The Dashboard's one-time "take a quick tour" offer (installs set up before the tour existed).
    private(set) var isOfferVisible = false
    /// Each target's frame in global coordinates, per registered view: a target can be on screen more than once
    /// while tabs change (each tab's root has its own Quick Add button).
    private var frames: [TourTarget: [UUID: CGRect]] = [:]
    @ObservationIgnored private var pendingStart: Task<Void, Never>?
    private let router: AppRouter
    private let defaults: UserDefaults

    init(router: AppRouter, defaults: UserDefaults = .standard) {
        self.router = router
        self.defaults = defaults
    }

    var isRunning: Bool { stepIndex != nil }

    var currentStep: TourStep? { stepIndex.map { TourStep.all[$0] } }

    private var policy: TourLaunchPolicy {
        TourLaunchPolicy.current(arguments: ProcessInfo.processInfo.arguments, defaults: defaults)
    }

    func frame(of target: TourTarget) -> CGRect? {
        frames[target]?.values.first
    }

    // MARK: Launch

    /// After the first-launch check: an install already set up is offered the tour once.
    func appLaunched(onboardingCompleted: Bool) {
        isOfferVisible = !isRunning && policy.offersTour(onboardingCompletedAtLaunch: onboardingCompleted)
    }

    /// A fresh install finished onboarding: the tour starts once the setup sheet has slid away.
    func onboardingFinished() {
        guard policy.startsAfterOnboarding else { return }
        pendingStart?.cancel()
        pendingStart = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            start()
        }
    }

    func acceptOffer() {
        defaults.set(true, forKey: TutorialSettings.offerAnsweredKey)
        start()
    }

    func declineOffer() {
        defaults.set(true, forKey: TutorialSettings.offerAnsweredKey)
        isOfferVisible = false
    }

    // MARK: Steps

    /// Starts from the first stop: after onboarding, from the offer, or from Settings › Show the Tour Again.
    func start() {
        pendingStart?.cancel()
        pendingStart = nil
        defaults.set(true, forKey: TutorialSettings.tourSeenKey)
        isOfferVisible = false
        show(0)
    }

    /// Next stop, or the end after the last one ("Done").
    func next() {
        guard let stepIndex else { return }
        if stepIndex + 1 < TourStep.all.count {
            show(stepIndex + 1)
        } else {
            finish()
        }
    }

    /// Skip tour and Done both end it where the user is.
    func finish() {
        stepIndex = nil
    }

    private func show(_ index: Int) {
        stepIndex = index
        switch TourStep.all[index].screen {
        case .dashboard:
            router.show(.dashboard)
        case .budget:
            // The transactions list, keeping whatever filter the user had.
            router.showBudget(.transactions, filter: router.budgetFilter)
        case .wishlist:
            router.show(.wishlist)
        case .tasks:
            router.show(.tasks)
        case .more:
            // More's first screen, where the Settings row is.
            router.morePath = []
            router.show(.more)
        }
    }

    // MARK: Targets

    func register(_ target: TourTarget, id: UUID, frame: CGRect) {
        frames[target, default: [:]][id] = frame
    }

    func unregister(_ target: TourTarget, id: UUID) {
        frames[target]?[id] = nil
    }
}

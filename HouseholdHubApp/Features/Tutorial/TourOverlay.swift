import SwiftUI

extension View {
    /// Sprint 24: marks the view the tour's `target` stop spotlights. The frame is reported in global coordinates
    /// straight to `TourController`: a preference would not cross the tab view's and navigation stacks' hosting
    /// boundaries on its way to the root.
    func tourTarget(_ target: TourTarget) -> some View {
        modifier(TourTargetModifier(target: target))
    }
}

private struct TourTargetModifier: ViewModifier {
    let target: TourTarget
    @State private var id = UUID()
    @State private var frame: CGRect?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { newFrame in
                frame = newFrame
                TourController.shared.register(target, id: id, frame: newFrame)
            }
            // A tab coming back keeps its geometry, so no change is reported: register the last frame again.
            .onAppear {
                if let frame {
                    TourController.shared.register(target, id: id, frame: frame)
                }
            }
            .onDisappear { TourController.shared.unregister(target, id: id) }
    }
}

/// Sprint 24: the tour's spotlight over the whole app, tab bar included. Everything is dimmed except a rounded
/// cut-out around the current stop's target, with a callout beside it. Taps outside the callout do nothing, so the
/// app underneath can't be used mid-tour; "Skip tour" is always there.
struct TourOverlay: View {
    @State private var tour = TourController.shared
    @State private var router = AppRouter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let step = tour.currentStep, let index = tour.stepIndex {
                let target = tour.frame(of: step.target)
                TourSpotlight(
                    step: step, index: index, count: TourStep.all.count, target: target, screen: screenName,
                    onNext: { tour.next() }, onSkip: { tour.finish() }
                )
                // Reduce Motion: each stop cross-fades in; otherwise the cut-out and callout move to the next target.
                .id(reduceMotion ? index : -1)
                .transition(.opacity)
                .animation(reduceMotion ? nil : Animation.snappy, value: target)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: tour.stepIndex)
    }

    /// The tab showing under the callout, for UI tests.
    private var screenName: String {
        switch router.tab {
        case .dashboard: "dashboard"
        case .budget: "budget"
        case .wishlist: "wishlist"
        case .tasks: "tasks"
        case .more: "more"
        }
    }
}

private struct TourSpotlight: View {
    let step: TourStep
    let index: Int
    let count: Int
    /// The target's frame in global coordinates; nil until the stop's screen has laid it out.
    let target: CGRect?
    let screen: String
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState private var headerFocused: Bool

    private static let cornerRadius: CGFloat = 14
    private static let corner = CGSize(width: cornerRadius, height: cornerRadius)
    /// Room the callout needs beside the cut-out; with less it docks at the bottom over the target.
    private static let calloutRoom: CGFloat = 240

    private var isLast: Bool { index + 1 == count }

    /// UI tests read the tab under the callout from the step's accessibility value; VoiceOver users never hear it.
    private var testScreen: String {
        ProcessInfo.processInfo.arguments.contains(LaunchArguments.uiTesting) ? screen : ""
    }

    var body: some View {
        ZStack {
            dimming
            calloutLayer
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onSkip() }
        .task(id: index) {
            // Each stop is announced and VoiceOver moves to its callout, so it is usable without seeing the highlight.
            let title = String(localized: step.title)
            let announcement = String(localized: "Step \(index + 1) of \(count): \(title)")
            AccessibilityNotification.Announcement(announcement).post()
            try? await Task.sleep(for: .milliseconds(350))
            headerFocused = true
        }
    }

    /// The dimmed screen with the target's cut-out. It takes every touch, the cut-out included, and is hidden from
    /// VoiceOver.
    private var dimming: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let hole = cutout(origin: proxy.frame(in: .global).origin, bounds: bounds)
            Path { path in
                path.addRect(bounds)
                if let hole {
                    path.addRoundedRect(in: hole, cornerSize: Self.corner)
                }
            }
            .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
            .overlay {
                if let hole {
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                        .frame(width: hole.width, height: hole.height)
                        .position(x: hole.midX, y: hole.midY)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {}
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// The target in this layer's coordinates, with a margin, kept on screen; nil when it isn't on screen.
    private func cutout(origin: CGPoint, bounds: CGRect) -> CGRect? {
        guard let target else { return nil }
        let local = target.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -8, dy: -8)
        let visible = local.intersection(bounds)
        return visible.isNull || visible.isEmpty ? nil : visible
    }

    /// The callout, inside the safe area: below the cut-out when there is room, else above it, else docked at the
    /// bottom. At accessibility text sizes it always docks at the bottom at full width.
    private var calloutLayer: some View {
        GeometryReader { proxy in
            // Placement looks at the whole target, even the part the screen edge hides.
            let size = proxy.size
            let reach = CGRect(x: 0, y: -size.height, width: size.width, height: size.height * 3)
            let hole = cutout(origin: proxy.frame(in: .global).origin, bounds: reach)
            let placement = calloutPlacement(hole: hole, height: proxy.size.height)
            callout
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 440)
                .padding(.horizontal, 16)
                .padding(.top, placement.top)
                .padding(.bottom, placement.bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placement.alignment)
        }
    }

    private struct Placement {
        var alignment: Alignment
        var top: CGFloat
        var bottom: CGFloat
    }

    private func calloutPlacement(hole: CGRect?, height: CGFloat) -> Placement {
        let docked = Placement(alignment: .bottom, top: 8, bottom: 8)
        guard !typeSize.isAccessibilitySize, let hole else { return docked }
        if height - hole.maxY - 12 >= Self.calloutRoom {
            return Placement(alignment: .top, top: max(hole.maxY + 12, 8), bottom: 8)
        }
        if hole.minY - 12 >= Self.calloutRoom {
            return Placement(alignment: .bottom, top: 8, bottom: max(height - hole.minY + 12, 8))
        }
        return docked
    }

    /// Wraps and never truncates; scrolls only when even the whole screen can't hold it (the largest text sizes).
    private var callout: some View {
        ViewThatFits(in: .vertical) {
            calloutContent
            ScrollView { calloutContent }
        }
        .padding(20)
        .themedSurface(cornerRadius: 20, standard: .background)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour.callout")
    }

    private var calloutContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(index + 1) of \(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Step \(index + 1) of \(count)"))
                Text(step.title)
                    .themedFont(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(Text(verbatim: testScreen))
            .accessibilityIdentifier("tour.step")
            .accessibilityFocused($headerFocused)
            Text(step.message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("tour.message")
            buttons
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                nextButton
                skipButton
            }
        } else {
            HStack {
                skipButton
                Spacer(minLength: 12)
                nextButton
            }
        }
    }

    private var nextButton: some View {
        Button(action: onNext) {
            // "Next" alone is already Upcoming's heading in Spanish, so the tour's button has its own key.
            isLast ? Text("Done") : Text(String(localized: "tour.next", defaultValue: "Next"))
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("tour.next")
    }

    private var skipButton: some View {
        Button("Skip tour", action: onSkip)
            .accessibilityIdentifier("tour.skip")
    }
}

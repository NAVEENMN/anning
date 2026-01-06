import SwiftUI
import AppKit

/// A vertical split (top/bottom) that persists the bottom pane fraction.
/// - bottomFraction: fraction of total height allocated to the bottom pane (0..1)
struct PersistentVSplitView<Top: View, Bottom: View>: NSViewRepresentable {
    @Binding var bottomFraction: Double
    let minTop: CGFloat
    let minBottom: CGFloat

    let top: Top
    let bottom: Bottom

    init(
        bottomFraction: Binding<Double>,
        minTop: CGFloat = 320,
        minBottom: CGFloat = 240,
        @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self._bottomFraction = bottomFraction
        self.minTop = minTop
        self.minBottom = minBottom
        self.top = top()
        self.bottom = bottom()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSplitView {
        let split = NSSplitView()
        split.isVertical = false
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false

        // IMPORTANT: order is bottom first, then top.
        // For horizontal split views, divider position is measured from the bottom.
        let bottomHost = NSHostingView(rootView: AnyView(bottom))
        let topHost = NSHostingView(rootView: AnyView(top))

        bottomHost.translatesAutoresizingMaskIntoConstraints = false
        topHost.translatesAutoresizingMaskIntoConstraints = false

        split.addArrangedSubview(bottomHost)
        split.addArrangedSubview(topHost)

        context.coordinator.split = split
        context.coordinator.bottomHost = bottomHost
        context.coordinator.topHost = topHost

        // Observe divider moves
        split.postsFrameChangedNotifications = true

        let nc = NotificationCenter.default
        context.coordinator.willResizeObs = nc.addObserver(
            forName: NSSplitView.willResizeSubviewsNotification,
            object: split,
            queue: .main
        ) { [weak c = context.coordinator] _ in
            c?.isDragging = true
        }

        context.coordinator.didResizeObs = nc.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification,
            object: split,
            queue: .main
        ) { [weak c = context.coordinator] _ in
            guard let c else { return }
            c.isDragging = false
            c.captureFractionAndStore()
        }

        return split
    }

    func updateNSView(_ split: NSSplitView, context: Context) {
        context.coordinator.bottomHost?.rootView = AnyView(bottom)
        context.coordinator.topHost?.rootView = AnyView(top)

        // Apply persisted fraction (don't fight the user while dragging)
        context.coordinator.applyFractionIfNeeded(
            desired: bottomFraction,
            minTop: minTop,
            minBottom: minBottom
        )
    }

    final class Coordinator: NSObject {
        weak var split: NSSplitView?
        weak var bottomHost: NSHostingView<AnyView>?
        weak var topHost: NSHostingView<AnyView>?

        var willResizeObs: NSObjectProtocol?
        var didResizeObs: NSObjectProtocol?

        var isDragging = false
        var isApplying = false

        deinit {
            let nc = NotificationCenter.default
            if let willResizeObs { nc.removeObserver(willResizeObs) }
            if let didResizeObs { nc.removeObserver(didResizeObs) }
        }

        func applyFractionIfNeeded(desired: Double, minTop: CGFloat, minBottom: CGFloat) {
            guard let split, !isDragging, !isApplying else { return }
            guard split.bounds.height > 10 else { return }

            let divider = split.dividerThickness
            let total = max(1, split.bounds.height - divider)

            let currentBottom = split.subviews.first?.frame.height ?? 0
            let currentFrac = Double(currentBottom / total)

            // If already close, don't re-apply (avoids jitter)
            if abs(currentFrac - desired) < 0.01 { return }

            var bottomH = CGFloat(desired) * total
            bottomH = min(max(bottomH, minBottom), total - minTop)

            isApplying = true
            split.setPosition(bottomH, ofDividerAt: 0)
            split.layoutSubtreeIfNeeded()
            isApplying = false
        }

        func captureFractionAndStore() {
            guard let split, !isApplying else { return }
            guard split.bounds.height > 10 else { return }

            let divider = split.dividerThickness
            let total = max(1, split.bounds.height - divider)
            let bottomH = split.subviews.first?.frame.height ?? 0
            let frac = Double(bottomH / total)

            // Clamp to sensible range
            let clamped = min(max(frac, 0.10), 0.90)

            // Write back through SwiftUI binding indirectly:
            // We can't access the binding here, but updateNSView will pick up changes
            // when the @SceneStorage value changes. So we post a notification.
            NotificationCenter.default.post(
                name: .anningSplitFractionChanged,
                object: clamped
            )
        }
    }
}

extension Notification.Name {
    static let anningSplitFractionChanged = Notification.Name("anningSplitFractionChanged")
}


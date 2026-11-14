import AppKit
import Common

// Hold `scrolling-swipe-modifiers` and swipe two fingers sideways, or turn a mouse wheel, to step through the
// columns of a scrolling workspace. A global NSEvent monitor can only watch, and the app under the pointer would
// scroll as well, so this is an event tap: it swallows the gestures it acts on and passes everything else through

@MainActor private var swipeTap: CFMachPort? = nil
@MainActor private var swipeTapSource: CFRunLoopSource? = nil
@MainActor private var swipeTracker = ScrollingSwipeTracker()

@MainActor func syncScrollingSwipe(_ config: Config) {
    if (config.scrollingSwipeModifiers != nil) == (swipeTap != nil) { return }
    if let tap = swipeTap {
        CGEvent.tapEnable(tap: tap, enable: false)
        if let swipeTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), swipeTapSource, .commonModes) }
        swipeTap = nil
        swipeTapSource = nil
        return
    }
    let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    // The tap lives on the main run loop, so the callback runs on the main thread. Only plain values cross into
    // the main actor; CGEvent isn't Sendable
    guard let tap = unsafe CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: { _, type, event, _ in
            let consume: Bool = switch type {
                case .tapDisabledByTimeout, .tapDisabledByUserInput:
                    // macOS switches a tap off when a callback is slow. Switch it back on
                    MainActor.assumeIsolated { reenableSwipeTap() }
                case .scrollWheel:
                    MainActor.assumeIsolated { [sample = ScrollSample(event), flags = event.flags] in
                        handleSwipe(sample, flags)
                    }
                default:
                    false
            }
            return consume ? nil : unsafe Unmanaged.passUnretained(event)
        },
        userInfo: nil,
    ) else { return } // No Accessibility permission yet. The next config reload tries again
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    swipeTap = tap
    swipeTapSource = source
}

@MainActor
private func reenableSwipeTap() -> Bool {
    if let swipeTap { CGEvent.tapEnable(tap: swipeTap, enable: true) }
    return false
}

/// - Returns: whether to swallow the event
@MainActor
private func handleSwipe(_ sample: ScrollSample, _ flags: CGEventFlags) -> Bool {
    let modifiers = config.scrollingSwipeModifiers ?? []
    let root = focus.workspace.rootTilingContainer
    let decision = swipeTracker.handle(
        sample,
        isArmed: TrayMenuModel.shared.isEnabled && !modifiers.isEmpty && flags.containsAll(modifiers) &&
            root.layout == .scrolling,
    )
    if let step = decision.step {
        pendingSwipeSteps = max(-maxPendingSwipeSteps, min(maxPendingSwipeSteps, pendingSwipeSteps + step))
        if !isRunningSwipeSteps {
            isRunningSwipeSteps = true
            Task.startUnstructured { @MainActor in
                defer {
                    isRunningSwipeSteps = false
                    pendingSwipeSteps = 0
                }
                try await runPendingSwipeSteps()
            }
        }
    }
    return decision.consume
}

/// A wheel spun fast gives steps faster than focus can run them, and two focus commands running at once trip over
/// each other at every await. So steps queue up here and run one after another
@MainActor private var pendingSwipeSteps = 0
@MainActor private var isRunningSwipeSteps = false
private let maxPendingSwipeSteps = 4

@MainActor
private func runPendingSwipeSteps() async throws {
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    while pendingSwipeSteps != 0 {
        let step = pendingSwipeSteps > 0 ? 1 : -1
        pendingSwipeSteps -= step
        let root = focus.workspace.rootTilingContainer
        guard root.layout == .scrolling else { return }
        let direction: CardinalDirection = switch (root.orientation, step > 0) {
            case (.h, true): .right
            case (.h, false): .left
            case (.v, true): .down
            case (.v, false): .up
        }
        try await runLightSession(.scrollingSwipe, token) {
            var args = FocusCmdArgs(rawArgs: [].slice, cardinalOrDfsDirection: .direction(direction))
            // The swipe walks the columns. Floating windows aren't columns, and treating them as tiles means AX
            // calls in the middle of the command
            args.floatingAsTiling = false
            _ = await FocusCommand(args: args).run(.defaultEnv, .emptyStdin)
        }
    }
}

extension CGEventFlags {
    fileprivate func containsAll(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        (!modifiers.contains(.shift) || contains(.maskShift)) &&
            (!modifiers.contains(.option) || contains(.maskAlternate)) &&
            (!modifiers.contains(.control) || contains(.maskControl)) &&
            (!modifiers.contains(.command) || contains(.maskCommand))
    }
}

/// What the tracker needs from a scroll event. Separate from CGEvent so the tracker can be tested
struct ScrollSample: Equatable {
    enum Phase { case none, began, changed, ended }

    /// Positive moves content right, the same sign apps see, so natural scrolling is already applied
    var deltaX: CGFloat
    var deltaY: CGFloat
    /// A trackpad or Magic Mouse rather than a wheel with notches
    var isContinuous: Bool
    var phase: Phase
    var momentumPhase: Phase
}

extension ScrollSample {
    /// Sideways or up and down, whichever moved more. Up counts like left
    fileprivate var dominantDelta: CGFloat { abs(deltaX) >= abs(deltaY) ? deltaX : deltaY }

    init(_ event: CGEvent) {
        self.init(
            deltaX: CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)),
            deltaY: CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)),
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            phase: .init(gesturePhase: event.getIntegerValueField(.scrollWheelEventScrollPhase)),
            momentumPhase: .init(momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase)),
        )
    }
}

extension ScrollSample.Phase {
    // CGScrollPhase: began 1, changed 2, ended 4, cancelled 8, may begin 128
    fileprivate init(gesturePhase raw: Int64) {
        self = switch raw {
            case 1: .began
            case 2: .changed
            case 4, 8: .ended
            default: .none
        }
    }

    // CGMomentumScrollPhase: begin 1, continue 2, end 3
    fileprivate init(momentumPhase raw: Int64) {
        self = switch raw {
            case 1: .began
            case 2: .changed
            case 3: .ended
            default: .none
        }
    }
}

/// Turns scroll events into column steps. A trackpad swipe steps once, however long it is, and the tracker keeps
/// swallowing that swipe's events to the end of its momentum, so the app under the pointer never scrolls. Without
/// the modifiers held when a swipe begins, the whole swipe passes through untouched
struct ScrollingSwipeTracker {
    /// Points of sideways travel before a swipe counts
    static let threshold: CGFloat = 30

    private var isConsuming = false
    private var hasStepped = false
    private var accumulated: CGFloat = 0
    private var wheelAccumulated: CGFloat = 0

    /// - Parameter isArmed: the modifiers are held and the focused workspace is scrolling
    /// - Returns: whether to swallow the event, and +1 or -1 to step to the next or previous column
    mutating func handle(_ sample: ScrollSample, isArmed: Bool) -> (consume: Bool, step: Int?) {
        if !sample.isContinuous {
            // A wheel notch is one step. Vertical wheels count too, wheel down for the next column
            guard isArmed else { return (false, nil) }
            let delta = sample.dominantDelta
            return (true, delta == 0 ? nil : delta < 0 ? 1 : -1)
        }
        if sample.phase == .none && sample.momentumPhase == .none {
            // Smooth-scrolling wheels, like Logitech's with Options+, send continuous events with no gesture phases.
            // There's no swipe to count once, so every threshold's worth of spin is a step
            guard isArmed else {
                wheelAccumulated = 0
                return (false, nil)
            }
            wheelAccumulated += sample.dominantDelta
            guard abs(wheelAccumulated) >= ScrollingSwipeTracker.threshold else { return (true, nil) }
            let step = wheelAccumulated < 0 ? 1 : -1
            wheelAccumulated = 0
            return (true, step)
        }
        if sample.phase == .began {
            isConsuming = isArmed
            hasStepped = false
            accumulated = 0
        }
        guard isConsuming else { return (false, nil) }
        var step: Int? = nil
        if !hasStepped && sample.momentumPhase == .none {
            accumulated += sample.dominantDelta
            if abs(accumulated) >= ScrollingSwipeTracker.threshold {
                // Fingers moving left drag the strip left, which brings in the column on the right
                step = accumulated < 0 ? 1 : -1
                hasStepped = true
            }
        }
        if sample.momentumPhase == .ended {
            isConsuming = false
        }
        return (true, step)
    }
}

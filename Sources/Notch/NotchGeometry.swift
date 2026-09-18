import AppKit

/// The display's *own* notch — the camera housing on a MacBook, not ours.
///
/// Worth naming, because it is the one piece of the screen that is not a screen:
/// pixels drawn there are behind a hole, not merely covered.
struct HardwareNotch: Equatable {
    let width: CGFloat
    let height: CGFloat
}

/// Everything the geometry maths needs from a screen, so it can be faked in tests.
protocol ScreenDescribing {
    var frameValue: CGRect { get }
    var visibleFrameValue: CGRect { get }
    var hardwareNotch: HardwareNotch? { get }
    var displayIdentifier: String? { get }
}

extension ScreenDescribing {
    /// Most displays have none, and most tests do not care.
    var hardwareNotch: HardwareNotch? { nil }
    var displayIdentifier: String? { nil }
}

extension NSScreen: ScreenDescribing {
    var frameValue: CGRect { frame }
    var visibleFrameValue: CGRect { visibleFrame }

    /// Unlike `CGDirectDisplayID`, this UUID survives display reconfiguration
    /// and restarts, so a saved choice still names the same physical monitor.
    var displayIdentifier: String? {
        let screenNumber = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = deviceDescription[screenNumber] as? NSNumber,
              let unmanaged = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)
        else { return nil }
        let uuid = unmanaged.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Measured from the two menu-bar strips *either side* of the notch, which
    /// is the only thing AppKit describes directly. `safeAreaInsets.top` gives
    /// the height; a display without a notch reports no auxiliary areas.
    var hardwareNotch: HardwareNotch? {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else {
            return nil
        }
        let width = frame.width - left.width - right.width
        let height = safeAreaInsets.top
        guard width > 0, height > 0 else { return nil }
        return HardwareNotch(width: width, height: height)
    }
}

enum NotchGeometry {
    /// Anchor to the physical display edge, even when the Dock or menu bar
    /// reserves part of the desktop. Showing or hiding either must not move
    /// a position the user chose.
    ///
    /// The rect is rounded out to whole points on purpose. AppKit rounds window
    /// frames anyway, and if it does the rounding the panel ends up a fraction
    /// larger than asked for — which leaves the content, laid out at its exact
    /// size, stopping short of the screen edge. A hairline of wallpaper along
    /// that edge is all it takes for the notch to read as floating rather than
    /// welded to the bezel.
    static func panelFrame(
        for screen: ScreenDescribing,
        panelSize: CGSize,
        edge: NotchEdge = .right,
        // A user-chosen nudge along the edge, from `NotchViewModel.alongOffset`
        // — zero is the centred default this file always drew before the nudge
        // existed. Vertical edges read it as AppKit's y running *down* the
        // screen (dragging the pill down increases it); horizontal edges read
        // it as x running right, which needs no such flip.
        alongOffset: CGFloat = 0,
        // The padding `panelSize` carries on *each* end beyond the visible
        // pill, reserved for a hover card that is not there right now —
        // `NotchViewModel.slack`. Clamping the offset by the padded size
        // would have left the pill only a sliver of room to move in on most
        // screens, since that padding is sized for the tallest possible card
        // and can be most of the panel. Clamping by the pill's own extent
        // instead — `panelSize` shrunk by this on each end — lets it travel
        // almost the full edge; the padding is free to run past the bezel,
        // since nothing is drawn there until a card actually opens.
        slack: CGFloat = 0,
        // The settings handle hangs past the body's trailing end. That part
        // of the padding must stay on screen even when the hover card may not.
        trailingExtent: CGFloat = 0
    ) -> CGRect {
        let full = screen.frameValue
        let width = panelSize.width.rounded(.up)
        let height = panelSize.height.rounded(.up)

        let origin: CGPoint
        switch edge {
        case .right:
            let y = clamp(full.midY - height / 2 - alongOffset,
                          min: full.minY - slack + trailingExtent, max: full.maxY - height + slack)
            origin = CGPoint(x: full.maxX - width, y: y)
        case .left:
            let y = clamp(full.midY - height / 2 - alongOffset,
                          min: full.minY - slack + trailingExtent, max: full.maxY - height + slack)
            origin = CGPoint(x: full.minX, y: y)
        case .top:
            let x = clamp(full.midX - width / 2 + alongOffset,
                          min: full.minX - slack, max: full.maxX - width + slack - trailingExtent)
            origin = CGPoint(x: x, y: full.maxY - height)
        case .bottom:
            let x = clamp(full.midX - width / 2 + alongOffset,
                          min: full.minX - slack, max: full.maxX - width + slack - trailingExtent)
            origin = CGPoint(x: x, y: full.minY)
        }

        return CGRect(
            x: origin.x.rounded(),
            y: origin.y.rounded(),
            width: width,
            height: height
        )
    }

    /// The offsets `panelFrame` can actually honour on this screen, read off
    /// the same clamp it applies: anything past either end draws exactly where
    /// that end does. Settings' position slider spans this, and a carry back
    /// onto the notch's own edge is held to it, so neither stores a place the
    /// notch cannot be drawn at.
    static func alongOffsetRange(
        for screen: ScreenDescribing,
        panelSize: CGSize,
        edge: NotchEdge,
        slack: CGFloat = 0,
        trailingExtent: CGFloat = 0
    ) -> ClosedRange<CGFloat> {
        let full = screen.frameValue
        if edge.isVertical {
            // `panelFrame` places y at midY - height/2 - offset.
            let height = panelSize.height.rounded(.up)
            let start = full.midY - height / 2
            let lower = start - (full.maxY - height + slack)
            let upper = start - (full.minY - slack + trailingExtent)
            // A pill longer than the screen has nowhere to slide, and `clamp`
            // pins it to its low y, which is this range's upper end.
            return lower <= upper ? lower...upper : upper...upper
        } else {
            // `panelFrame` places x at midX - width/2 + offset.
            let width = panelSize.width.rounded(.up)
            let start = full.midX - width / 2
            let lower = (full.minX - slack) - start
            let upper = (full.maxX - width + slack - trailingExtent) - start
            return lower <= upper ? lower...upper : lower...lower
        }
    }

    /// The offsets every one of several notches can be drawn at, since one
    /// offset drives them all. Nil when any of them has no range to offer yet,
    /// or when they have none in common: no end is then more right than
    /// another, and picking one would depend on which display came first.
    static func sharedRange(_ ranges: [ClosedRange<CGFloat>?]) -> ClosedRange<CGFloat>? {
        let known = ranges.compactMap { $0 }
        guard !known.isEmpty, known.count == ranges.count,
              let lower = known.map(\.lowerBound).max(),
              let upper = known.map(\.upperBound).min(),
              lower <= upper else { return nil }
        return lower...upper
    }

    /// The offset that centres the notch on `point` along `edge`, in the
    /// convention `panelFrame` reads: down a side edge, rightward along a
    /// horizontal one.
    static func alongOffset(centring point: CGPoint, on edge: NotchEdge,
                            in screen: ScreenDescribing) -> CGFloat {
        let full = screen.frameValue
        return edge.isVertical ? full.midY - point.y : point.x - full.midX
    }

    /// Where a carry from the move handle leaves the notch.
    ///
    /// Back on its own edge it slides by however far the pointer travelled
    /// along it, the way the ⌥-drag does, so a press that never moves leaves
    /// it where it was instead of jumping to centre on the handle. Until the
    /// pointer has really moved (`hasMoved`, the same slop that keeps a click
    /// from changing edges) it stays put: a hand is never perfectly still on
    /// a click, and a few points of it are not a choice of place. On another
    /// edge there is no distance to carry over, so it centres where the
    /// pointer let go.
    static func carriedOffset(
        from edge: NotchEdge,
        at offset: CGFloat,
        pressedAt press: CGPoint,
        to target: NotchEdge,
        releasedAt release: CGPoint,
        hasMoved: Bool,
        in screen: ScreenDescribing
    ) -> CGFloat {
        let landing = alongOffset(centring: release, on: target, in: screen)
        guard target == edge else { return landing }
        guard hasMoved else { return offset }
        return offset + landing - alongOffset(centring: press, on: edge, in: screen)
    }

    static func preferredScreen(
        from screens: [NSScreen],
        preference: DisplayPreference = .followActiveWindow
    ) -> NSScreen? {
        preferredScreen(from: screens, preference: preference, activeScreen: NSScreen.main)
    }

    /// Kept generic so display selection can be proved without relying on the
    /// monitors attached to the machine running the tests.
    static func preferredScreen<Screen: ScreenDescribing>(
        from screens: [Screen],
        preference: DisplayPreference,
        activeScreen: Screen?
    ) -> Screen? {
        if case .display(let id) = preference,
           let selected = screens.first(where: { $0.displayIdentifier == id }) {
            return selected
        }
        return activeScreen ?? screens.first
    }

    /// Keeps a dragged offset from pushing the visible pill off the screen it
    /// is on. A plain `ClosedRange` clamp would trap if the pill were ever
    /// taller or wider than the screen, which a very small display could
    /// make true.
    private static func clamp(_ value: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        guard lo <= hi else { return lo }
        return Swift.min(Swift.max(value, lo), hi)
    }
}

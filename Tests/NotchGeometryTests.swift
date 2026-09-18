import XCTest
@testable import Codenotch

private struct FakeScreen: ScreenDescribing {
    var frameValue: CGRect
    var visibleFrameValue: CGRect
    var displayIdentifier: String? = nil
}

final class NotchGeometryTests: XCTestCase {
    private let screen = FakeScreen(
        frameValue: CGRect(x: 0, y: 0, width: 1800, height: 1169),
        visibleFrameValue: CGRect(x: 0, y: 0, width: 1800, height: 1132)
    )

    func testPanelHugsTheRightEdgeAndIsVerticallyCentred() {
        let size = CGSize(width: 334, height: 484)
        let frame = NotchGeometry.panelFrame(for: screen, panelSize: size)
        XCTAssertEqual(frame.maxX, 1800, accuracy: 0.001)
        // Centring is allowed to be half a point out: the frame is rounded to
        // whole points so the right-hand edge can be exact, and being flush
        // against the bezel matters where half a point of vertical drift does not.
        XCTAssertEqual(frame.midY, screen.frameValue.midY, accuracy: 0.5)
        XCTAssertEqual(frame.size, size)
    }

    func testPanelFollowsAScreenWithANonZeroOrigin() {
        let secondary = FakeScreen(
            frameValue: CGRect(x: -2560, y: 200, width: 2560, height: 1440),
            visibleFrameValue: CGRect(x: -2560, y: 200, width: 2560, height: 1415)
        )
        let frame = NotchGeometry.panelFrame(for: secondary, panelSize: CGSize(width: 334, height: 484))
        XCTAssertEqual(frame.maxX, 0, accuracy: 0.001)
        XCTAssertEqual(frame.midY, 920, accuracy: 0.5)
    }

    func testAChosenDisplayWinsOverTheActiveOne() {
        let active = FakeScreen(frameValue: .zero, visibleFrameValue: .zero,
                                displayIdentifier: "active")
        let chosen = FakeScreen(frameValue: CGRect(x: 100, y: 0, width: 100, height: 100),
                                visibleFrameValue: .zero, displayIdentifier: "chosen")

        let result = NotchGeometry.preferredScreen(
            from: [active, chosen], preference: .display("chosen"), activeScreen: active
        )

        XCTAssertEqual(result?.displayIdentifier, "chosen")
    }

    func testADisconnectedChoiceTemporarilyFallsBackToTheActiveDisplay() {
        let active = FakeScreen(frameValue: .zero, visibleFrameValue: .zero,
                                displayIdentifier: "active")

        let result = NotchGeometry.preferredScreen(
            from: [active], preference: .display("missing"), activeScreen: active
        )

        XCTAssertEqual(result?.displayIdentifier, "active")
    }

    func testFollowActiveWindowUsesTheActiveDisplay() {
        let first = FakeScreen(frameValue: .zero, visibleFrameValue: .zero,
                               displayIdentifier: "first")
        let active = FakeScreen(frameValue: .zero, visibleFrameValue: .zero,
                                displayIdentifier: "active")

        let result = NotchGeometry.preferredScreen(
            from: [first, active], preference: .followActiveWindow, activeScreen: active
        )

        XCTAssertEqual(result?.displayIdentifier, "active")
    }
}

/// `alongOffset` is how a ⌥-drag on the pill (`NotchWindowController.dragged`)
/// nudges it off the centred default. These pin down the sign convention —
/// get it wrong and the pill runs away from the cursor instead of following
/// it — and the clamp that keeps a drag from pushing it off the screen.
final class PanelOffsetTests: XCTestCase {
    private let screen = FakeScreen(
        frameValue: CGRect(x: 0, y: 0, width: 1800, height: 1169),
        visibleFrameValue: CGRect(x: 0, y: 0, width: 1800, height: 1132)
    )

    @MainActor
    func testDraggingToTheTrailingEndKeepsTheSettingsHandleOnScreen() {
        let secondary = FakeScreen(
            frameValue: CGRect(x: -1800, y: -200, width: 1800, height: 1169),
            visibleFrameValue: CGRect(x: -1800, y: -200, width: 1800, height: 1132)
        )
        for display in [screen, secondary] {
            for edge in NotchEdge.allCases {
                let model = NotchViewModel()
                model.edge = edge
                let frame = NotchGeometry.panelFrame(
                    for: display, panelSize: model.panelSize, edge: edge,
                    alongOffset: 10_000, slack: model.slack,
                    trailingExtent: model.trailingExtent
                )
                let handleEnd = model.slack + model.orbAlong + NotchLayout.orbHotZone / 2
                if edge.isVertical {
                    XCTAssertGreaterThanOrEqual(frame.maxY - handleEnd,
                                                display.frameValue.minY - 0.5)
                } else {
                    XCTAssertLessThanOrEqual(frame.minX + handleEnd,
                                             display.frameValue.maxX + 0.5)
                }
            }
        }
    }

    func testZeroOffsetChangesNothing() {
        let size = CGSize(width: 334, height: 484)
        let centred = NotchGeometry.panelFrame(for: screen, panelSize: size, edge: .right)
        let explicit = NotchGeometry.panelFrame(for: screen, panelSize: size, edge: .right, alongOffset: 0)
        XCTAssertEqual(centred, explicit)
    }

    /// A positive offset on a side edge moves the pill *down* — the direction
    /// `NotchWindowController.dragged` feeds it in when the pointer moves
    /// down, since `NSEvent`'s raw delta and AppKit's y-grows-up frame origin
    /// disagree about which way is positive.
    func testPositiveOffsetMovesASideEdgePanelDown() {
        let size = CGSize(width: 334, height: 484)
        let centred = NotchGeometry.panelFrame(for: screen, panelSize: size, edge: .right)
        let nudged = NotchGeometry.panelFrame(for: screen, panelSize: size, edge: .right, alongOffset: 100)
        XCTAssertEqual(nudged.midY, centred.midY - 100, accuracy: 0.5)
        // Still flush against the right-hand bezel — only the along axis moved.
        XCTAssertEqual(nudged.maxX, centred.maxX, accuracy: 0.001)
    }

    /// A positive offset on a top/bottom edge moves the pill *right* — no sign
    /// flip needed there, since `NSEvent.deltaX` and AppKit's x already agree.
    func testPositiveOffsetMovesATopEdgePanelRight() {
        let size = CGSize(width: 484, height: 120)
        let centred = NotchGeometry.panelFrame(for: screen, panelSize: size, edge: .top)
        let nudged = NotchGeometry.panelFrame(for: screen, panelSize: size, edge: .top, alongOffset: 100)
        XCTAssertEqual(nudged.midX, centred.midX + 100, accuracy: 0.5)
        XCTAssertEqual(nudged.maxY, centred.maxY, accuracy: 0.001)
    }

    /// `slack` is the padding `panelSize` carries beyond the visible pill,
    /// reserved for a hover card that may not be open. Clamping by the full
    /// panel — as if that padding had to stay on screen too — left almost no
    /// room to drag on a panel sized for the worst-case card. Clamping by the
    /// pill's own extent instead should let it travel nearly the whole edge.
    func testAnExtremeOffsetKeepsTheVisiblePillOnScreenRatherThanThePadding() {
        let slack = 400.0
        let size = CGSize(width: 334, height: 900)   // mostly hover-card padding
        let frame = NotchGeometry.panelFrame(
            for: screen, panelSize: size, edge: .right, alongOffset: 10_000, slack: slack
        )
        let pillTop = frame.maxY - slack
        let pillBottom = frame.minY + slack
        XCTAssertLessThanOrEqual(pillTop, screen.frameValue.maxY + 0.5)
        XCTAssertGreaterThanOrEqual(pillBottom, screen.frameValue.minY - 0.5)
    }

    /// Without `slack`'s allowance, the same drag would have clamped to
    /// keeping the *entire* padded panel on screen — which the real bug
    /// report was about: a handful of points of travel on a panel sized for
    /// four providers' worth of hover card.
    func testSlackWidensTheDraggableRangeBeyondClampingTheWholePanel() {
        let size = CGSize(width: 334, height: 900)
        let withoutSlack = NotchGeometry.panelFrame(
            for: screen, panelSize: size, edge: .right, alongOffset: 10_000, slack: 0
        )
        let withSlack = NotchGeometry.panelFrame(
            for: screen, panelSize: size, edge: .right, alongOffset: 10_000, slack: 400
        )
        XCTAssertLessThan(withSlack.minY, withoutSlack.minY)
    }
}

/// A hairline of wallpaper down the right-hand side is all it takes for the
/// notch to read as floating instead of welded to the bezel, and a fractional
/// panel frame is how that happens.
final class PanelEdgeTests: XCTestCase {
    private let screen = FakeScreen(
        frameValue: CGRect(x: 0, y: 0, width: 1800, height: 1169),
        visibleFrameValue: CGRect(x: 0, y: 0, width: 1800, height: 1132)
    )

    /// The real panel size is fractional — it is derived from the design
    /// frame's pixel ratios — which is exactly the case that used to leave a gap.
    func testAFractionalSizeStillLandsFlushOnTheEdge() {
        let fractional = CGSize(width: 334.3247863247863, height: 205.182905982906)
        let frame = NotchGeometry.panelFrame(for: screen, panelSize: fractional)
        XCTAssertEqual(frame.maxX, 1800, accuracy: 0.0001)
    }

    func testTheFrameIsIntegral() {
        let frame = NotchGeometry.panelFrame(
            for: screen,
            panelSize: CGSize(width: 334.3247863247863, height: 205.182905982906)
        )
        for value in [frame.minX, frame.minY, frame.width, frame.height] {
            XCTAssertEqual(value, value.rounded(), "\(value) is not a whole point")
        }
    }

    /// Rounding must never make the panel narrower than its content.
    func testItNeverRoundsBelowTheRequestedSize() {
        let requested = CGSize(width: 334.325, height: 205.183)
        let frame = NotchGeometry.panelFrame(for: screen, panelSize: requested)
        XCTAssertGreaterThanOrEqual(frame.width, requested.width)
        XCTAssertGreaterThanOrEqual(frame.height, requested.height)
    }

    func testItStaysFlushOnAScreenWithANonZeroOrigin() {
        let secondary = FakeScreen(
            frameValue: CGRect(x: -2560, y: 200, width: 2560, height: 1440),
            visibleFrameValue: CGRect(x: -2560, y: 200, width: 2560, height: 1415)
        )
        let frame = NotchGeometry.panelFrame(
            for: secondary,
            panelSize: CGSize(width: 334.3247863247863, height: 205.182905982906)
        )
        XCTAssertEqual(frame.maxX, 0, accuracy: 0.0001)
    }
}

/// Use an offset monitor and reserve desktop space on every side so accidental
/// dependencies on the primary display or visibleFrame are caught together.
final class ScreenAnchorRegressionTests: XCTestCase {
    func testEveryEdgeIgnoresDesktopReservationsAtEveryDragPosition() {
        let full = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let shown = FakeScreen(frameValue: full,
                               visibleFrameValue: full.insetBy(dx: 90, dy: 70))
        let hidden = FakeScreen(frameValue: full, visibleFrameValue: full)
        for edge in NotchEdge.allCases {
            let size = NotchPlacement.panelSize(edge: edge, length: 800, depth: 300)
            for offset: CGFloat in [-10000, -230, 0, 310, 10000] {
                let frame = NotchGeometry.panelFrame(for: shown, panelSize: size,
                                                     edge: edge, alongOffset: offset, slack: 200)
                XCTAssertEqual(frame, NotchGeometry.panelFrame(for: hidden, panelSize: size,
                                                                edge: edge, alongOffset: offset, slack: 200))
                switch edge {
                case .left: XCTAssertEqual(frame.minX, full.minX)
                case .right: XCTAssertEqual(frame.maxX, full.maxX)
                case .top: XCTAssertEqual(frame.maxY, full.maxY)
                case .bottom: XCTAssertEqual(frame.minY, full.minY)
                }
            }
        }
    }

    @MainActor func testCornerTooltipsStayInsideTheVisiblePartOfThePanel() {
        for size in NotchSize.allCases {
            for edge in NotchEdge.allCases {
                let model = NotchViewModel()
                model.edge = edge
                model.sizeScale = size.scale
                let length: CGFloat = edge.isVertical ? 300 : NotchLayout.cardWidth
                let ring = model.slack + model.ringCenter(index: 0) * size.scale
                XCTAssertEqual(model.tooltipAlong(index: 0, length: length), ring)
                // Both ends of the screen: the ring remains on screen, while a
                // card centred on it would lose its heading or its right edge.
                for range in [(ring - 45)...(ring + 900), (ring - 900)...(ring + 45)] {
                    model.visibleAlongRange = range
                    let centre = model.tooltipAlong(index: 0, length: length)
                    XCTAssertGreaterThanOrEqual(centre - length / 2, range.lowerBound - 0.0001)
                    XCTAssertLessThanOrEqual(centre + length / 2, range.upperBound + 0.0001)
                    XCTAssertNotEqual(centre, ring)
                    XCTAssertLessThanOrEqual(abs(ring - centre), length / 2 - NotchLayout.tailHeight / 2)
                }
                model.visibleAlongRange = (ring - 900)...(ring + 900)
                XCTAssertEqual(model.tooltipAlong(index: 0, length: length), ring)
            }
        }
    }
}

/// The size choice reaches the screen in the notch's own measurements, never
/// in the tooltip's. These pin the seam between the two.
final class ScaledMeasurementTests: XCTestCase {
    /// A scaled panel is still a panel: it has to land flush on the bezel like
    /// any other, or a large notch floats a hairline off the edge.
    func testAScaledPanelStillLandsFlushOnTheEdge() {
        let screen = FakeScreen(frameValue: CGRect(x: 0, y: 0, width: 1800, height: 1000),
                                visibleFrameValue: CGRect(x: 0, y: 0, width: 1800, height: 1000))
        let frame = NotchGeometry.panelFrame(
            for: screen,
            panelSize: CGSize(width: 200, height: 750),
            edge: .right
        )

        XCTAssertEqual(frame.maxX, 1800, accuracy: 0.001)
    }

    /// The notch's own end margin scales; the room reserved for the card does
    /// not. Scaling both would reserve space for a card that is never that big,
    /// and at the small end would reserve less than the card needs.
    func testSlackScalesTheNotchsMarginAndNotTheCards() {
        let cardBound = NotchLayout.slack(for: .right, maxCardHeight: 2000)
        XCTAssertEqual(NotchLayout.slack(for: .right, maxCardHeight: 2000, notchScale: 0.8),
                       cardBound,
                       "the card's half-extent was scaled with the notch")

        let marginBound = NotchLayout.slack(for: .right, maxCardHeight: 0)
        XCTAssertEqual(NotchLayout.slack(for: .right, maxCardHeight: 0, notchScale: 2),
                       marginBound * 2, accuracy: 0.001)
    }
}

/// Where the notch can go along its edge, and where a carry from the move
/// handle leaves it. The range has to agree with `panelFrame`'s clamp exactly:
/// a slider end the notch cannot follow, or an offset stored past the end, is
/// a dead stretch the next drag has to cross before anything moves.
final class NotchPositionTests: XCTestCase {
    private let screen = FakeScreen(
        frameValue: CGRect(x: 0, y: 0, width: 1800, height: 1169),
        visibleFrameValue: CGRect(x: 0, y: 0, width: 1800, height: 1132)
    )

    @MainActor
    private func frame(_ offset: CGFloat, on edge: NotchEdge, of model: NotchViewModel) -> CGRect {
        NotchGeometry.panelFrame(for: screen, panelSize: model.panelSize, edge: edge,
                                 alongOffset: offset, slack: model.slack,
                                 trailingExtent: model.trailingExtent)
    }

    @MainActor
    func testTheRangeEndsExactlyWhereTheClampDoes() {
        for edge in NotchEdge.allCases {
            let model = NotchViewModel()
            model.edge = edge
            let range = NotchGeometry.alongOffsetRange(
                for: screen, panelSize: model.panelSize, edge: edge,
                slack: model.slack, trailingExtent: model.trailingExtent
            )
            XCTAssertLessThan(range.lowerBound, 0, "\(edge)")
            XCTAssertGreaterThan(range.upperBound, 0, "\(edge)")
            XCTAssertEqual(frame(range.lowerBound, on: edge, of: model),
                           frame(-10_000, on: edge, of: model), "\(edge)")
            XCTAssertEqual(frame(range.upperBound, on: edge, of: model),
                           frame(10_000, on: edge, of: model), "\(edge)")
            // Just inside either end still moves it: no narrower than the clamp.
            XCTAssertNotEqual(frame(range.lowerBound + 5, on: edge, of: model),
                              frame(-10_000, on: edge, of: model), "\(edge)")
            XCTAssertNotEqual(frame(range.upperBound - 5, on: edge, of: model),
                              frame(10_000, on: edge, of: model), "\(edge)")
        }
    }

    func testAPillLongerThanTheScreenHasOnePlace() {
        let tiny = FakeScreen(frameValue: CGRect(x: 0, y: 0, width: 120, height: 90),
                              visibleFrameValue: CGRect(x: 0, y: 0, width: 120, height: 90))
        let size = CGSize(width: 400, height: 400)
        for edge in NotchEdge.allCases {
            let range = NotchGeometry.alongOffsetRange(for: tiny, panelSize: size, edge: edge)
            XCTAssertEqual(range.lowerBound, range.upperBound, "\(edge)")
            XCTAssertEqual(
                NotchGeometry.panelFrame(for: tiny, panelSize: size, edge: edge, alongOffset: range.lowerBound),
                NotchGeometry.panelFrame(for: tiny, panelSize: size, edge: edge, alongOffset: 0),
                "\(edge)"
            )
        }
    }

    @MainActor
    func testCentringOnAPointPutsTheNotchThere() {
        let point = CGPoint(x: 1200, y: 800)
        for edge in NotchEdge.allCases {
            let model = NotchViewModel()
            model.edge = edge
            let offset = NotchGeometry.alongOffset(centring: point, on: edge, in: screen)
            let placed = frame(offset, on: edge, of: model)
            if edge.isVertical {
                XCTAssertEqual(placed.midY, point.y, accuracy: 1, "\(edge)")
            } else {
                XCTAssertEqual(placed.midX, point.x, accuracy: 1, "\(edge)")
            }
        }
    }

    func testACarryBackOntoItsOwnEdgeSlidesByTheDistanceMoved() {
        let press = CGPoint(x: 1790, y: 700)
        XCTAssertEqual(
            NotchGeometry.carriedOffset(from: .right, at: 40, pressedAt: press,
                                        to: .right, releasedAt: press, in: screen),
            40, "a press that never moves leaves the notch where it was"
        )
        // 80pt further down the screen; AppKit's y grows up.
        XCTAssertEqual(
            NotchGeometry.carriedOffset(from: .right, at: 40, pressedAt: press,
                                        to: .right, releasedAt: CGPoint(x: 1770, y: 620), in: screen),
            120
        )
        XCTAssertEqual(
            NotchGeometry.carriedOffset(from: .top, at: -30, pressedAt: CGPoint(x: 900, y: 1160),
                                        to: .top, releasedAt: CGPoint(x: 980, y: 1150), in: screen),
            50
        )
    }

    func testACarryToAnotherEdgeCentresWhereItLetGo() {
        let press = CGPoint(x: 1790, y: 700)
        XCTAssertEqual(
            NotchGeometry.carriedOffset(from: .right, at: 40, pressedAt: press,
                                        to: .bottom, releasedAt: CGPoint(x: 1100, y: 10), in: screen),
            200
        )
        XCTAssertEqual(
            NotchGeometry.carriedOffset(from: .right, at: 40, pressedAt: press,
                                        to: .left, releasedAt: CGPoint(x: 5, y: 300), in: screen),
            284.5
        )
    }

    @MainActor
    func testTheTargetZoneShowsWhereTheNotchWouldLand() {
        let size = CGSize(width: 1800, height: 1169)
        let zones = EdgeDropZones(target: .right, targetOffset: 200, size: size,
                                  restingDepth: 40, restingLength: 160)
        XCTAssertEqual(zones.frame(for: .right).midY, size.height / 2 + 200, accuracy: 0.5)
        XCTAssertEqual(zones.frame(for: .left).midY, size.height / 2, accuracy: 0.5,
                       "the zones not under the pointer stay centred")

        let far = EdgeDropZones(target: .top, targetOffset: 10_000, size: size,
                                restingDepth: 40, restingLength: 160)
        XCTAssertEqual(far.frame(for: .top).maxX, size.width, "kept whole on screen")
    }

    /// A notch slid to the top of the right edge has its handle nearer the top
    /// edge than the right one. A click on it is not a move.
    @MainActor
    func testAClickOnTheHandleNearACornerKeepsTheEdge() {
        let size = CGSize(width: 1800, height: 1169)
        let nearTheCorner = CGPoint(x: 1780, y: 8)
        XCTAssertEqual(EdgeDropZones.target(from: .right, hasMoved: false, at: nearTheCorner, in: size),
                       .right)
        XCTAssertEqual(EdgeDropZones.target(from: .right, hasMoved: true, at: nearTheCorner, in: size),
                       .top)
    }

    func testDisplaysShareOnlyTheOffsetsEveryOneCanShow() {
        XCTAssertEqual(NotchGeometry.sharedRange([-400...400, -250...600]), -250...400)
        XCTAssertNil(NotchGeometry.sharedRange([]), "no display, no range")
        XCTAssertNil(NotchGeometry.sharedRange([-400...400, nil]), "one of them is mid-move")
        XCTAssertNil(NotchGeometry.sharedRange([-400...(-300), 300...400]),
                     "nothing in common, and no end is more right than another")
    }
}

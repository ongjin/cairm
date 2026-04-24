import XCTest
@testable import Cairn

final class HistoryNavigationInputRouterTests: XCTestCase {
    func test_sideButtonDownRoutesBackAndConsumesMatchingUp() {
        let router = HistoryNavigationInputRouter()

        XCTAssertEqual(router.routeOtherMouseDown(buttonNumber: 3), .navigate(.back))
        XCTAssertEqual(router.routeOtherMouseUp(buttonNumber: 3), .consume)
    }

    func test_sideButtonUpWithoutDownStillRoutesBack() {
        let router = HistoryNavigationInputRouter()

        XCTAssertEqual(router.routeOtherMouseUp(buttonNumber: 3), .navigate(.back))
    }

    func test_forwardSideButtonRoutesForward() {
        let router = HistoryNavigationInputRouter()

        XCTAssertEqual(router.routeOtherMouseDown(buttonNumber: 4), .navigate(.forward))
    }

    func test_systemDefinedAuxSideButtonDownRoutesHistoryNavigationAndConsumesMatchingUp() {
        let router = HistoryNavigationInputRouter()

        XCTAssertEqual(router.routeAuxMouseButtons(changedButtons: 1 << 3, pressedButtons: 1 << 3), .navigate(.back))
        XCTAssertEqual(router.routeAuxMouseButtons(changedButtons: 1 << 3, pressedButtons: 0), .consume)
        XCTAssertEqual(router.routeAuxMouseButtons(changedButtons: 1 << 4, pressedButtons: 1 << 4), .navigate(.forward))
        XCTAssertEqual(router.routeAuxMouseButtons(changedButtons: 1 << 4, pressedButtons: 0), .consume)
    }

    func test_systemDefinedOtherAuxMouseButtonsPassThrough() {
        let router = HistoryNavigationInputRouter()

        XCTAssertEqual(router.routeAuxMouseButtons(changedButtons: 1, pressedButtons: 1), .passThrough)
        XCTAssertEqual(router.routeAuxMouseButtons(changedButtons: 1 << 2, pressedButtons: 1 << 2), .passThrough)
    }

    func test_horizontalSwipeRoutesHistoryNavigation() {
        XCTAssertEqual(HistoryNavigationInputRouter.routeSwipe(deltaX: -1, deltaY: 0), .navigate(.forward))
        XCTAssertEqual(HistoryNavigationInputRouter.routeSwipe(deltaX: 1, deltaY: 0), .navigate(.back))
    }

    func test_verticalOrZeroSwipePassesThrough() {
        XCTAssertEqual(HistoryNavigationInputRouter.routeSwipe(deltaX: 0, deltaY: 0), .passThrough)
        XCTAssertEqual(HistoryNavigationInputRouter.routeSwipe(deltaX: 1, deltaY: 2), .passThrough)
    }

    func test_otherMouseButtonsPassThrough() {
        let router = HistoryNavigationInputRouter()

        XCTAssertEqual(router.routeOtherMouseDown(buttonNumber: 2), .passThrough)
        XCTAssertEqual(router.routeOtherMouseUp(buttonNumber: 2), .passThrough)
    }

    func test_commandArrowKeyDownRoutesHistoryNavigation() {
        XCTAssertEqual(
            HistoryNavigationInputRouter.routeKeyDown(keyCode: HistoryNavigationInputRouter.leftArrowKeyCode, modifiers: .command),
            .navigate(.back)
        )
        XCTAssertEqual(
            HistoryNavigationInputRouter.routeKeyDown(keyCode: HistoryNavigationInputRouter.rightArrowKeyCode, modifiers: .command),
            .navigate(.forward)
        )
    }

    func test_commandBracketKeyDownRoutesHistoryNavigation() {
        XCTAssertEqual(
            HistoryNavigationInputRouter.routeKeyDown(keyCode: HistoryNavigationInputRouter.leftBracketKeyCode, modifiers: .command),
            .navigate(.back)
        )
        XCTAssertEqual(
            HistoryNavigationInputRouter.routeKeyDown(keyCode: HistoryNavigationInputRouter.rightBracketKeyCode, modifiers: .command),
            .navigate(.forward)
        )
    }

    func test_modifiedCommandArrowPassesThroughForTabSwitching() {
        XCTAssertEqual(
            HistoryNavigationInputRouter.routeKeyDown(keyCode: HistoryNavigationInputRouter.leftArrowKeyCode, modifiers: [.command, .option]),
            .passThrough
        )
    }
}

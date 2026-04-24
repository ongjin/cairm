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

    func test_modifiedCommandArrowPassesThroughForTabSwitching() {
        XCTAssertEqual(
            HistoryNavigationInputRouter.routeKeyDown(keyCode: HistoryNavigationInputRouter.leftArrowKeyCode, modifiers: [.command, .option]),
            .passThrough
        )
    }
}

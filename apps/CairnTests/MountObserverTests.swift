import XCTest
@testable import Cairn

final class MountObserverTests: XCTestCase {
    /// Basic sanity: freshly-constructed observer reflects the current mount state.
    /// Cannot simulate real mount/unmount in unit test; M1.3 E2E handles that.
    func test_initial_volumes_match_nsworkspace_snapshot() {
        let observer = MountObserver()
        let expected = Set(
            FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                   options: .skipHiddenVolumes) ?? []
        )
        XCTAssertEqual(Set(observer.volumes), expected)
    }
}

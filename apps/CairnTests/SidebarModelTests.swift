import XCTest
@testable import Cairn

final class SidebarModelTests: XCTestCase {
    /// MountObserver is injected so tests can stub the volumes list via a test-only
    /// helper on MountObserver (see setTestVolumes).
    private var observer: MountObserver!

    override func setUpWithError() throws {
        observer = MountObserver()
    }

    func test_locations_starts_with_computer_root_first() {
        let model = SidebarModel(mountObserver: observer)
        XCTAssertEqual(model.locations.first, URL(fileURLWithPath: "/"))
    }

    func test_locations_includes_mounted_volumes() {
        let model = SidebarModel(mountObserver: observer)
        // Every entry in observer.volumes should appear in model.locations.
        for vol in observer.volumes {
            XCTAssertTrue(model.locations.contains(vol),
                          "Expected \(vol) in locations but got \(model.locations)")
        }
    }

    func test_icloud_url_present_iff_path_exists() {
        let model = SidebarModel(mountObserver: observer)
        let expected = FileManager.default.fileExists(
            atPath: SidebarModel.iCloudDrivePath.path)
        XCTAssertEqual(model.iCloudURL != nil, expected)
    }
}

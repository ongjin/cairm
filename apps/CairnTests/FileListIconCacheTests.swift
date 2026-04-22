import XCTest
import AppKit
@testable import Cairn

final class FileListIconCacheTests: XCTestCase {
    func test_same_extension_returns_cached_instance() {
        let cache = FileListIconCache()
        let img1 = cache.icon(forPath: "/tmp/a.txt", isDirectory: false)
        let img2 = cache.icon(forPath: "/tmp/b.txt", isDirectory: false)
        XCTAssertTrue(img1 === img2, "Same ext should return cached NSImage instance")
    }

    func test_different_extensions_return_distinct_images() {
        let cache = FileListIconCache()
        let img1 = cache.icon(forPath: "/tmp/a.txt", isDirectory: false)
        let img2 = cache.icon(forPath: "/tmp/a.json", isDirectory: false)
        XCTAssertNotNil(img1)
        XCTAssertNotNil(img2)
    }

    func test_directory_is_cached_separately() {
        let cache = FileListIconCache()
        let file = cache.icon(forPath: "/tmp/a.txt", isDirectory: false)
        let dir = cache.icon(forPath: "/tmp/a.txt", isDirectory: true)
        XCTAssertNotNil(file)
        XCTAssertNotNil(dir)
    }
}

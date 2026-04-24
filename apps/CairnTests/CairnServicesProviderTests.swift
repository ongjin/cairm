import AppKit
import XCTest
@testable import Cairn

@MainActor
final class CairnServicesProviderTests: XCTestCase {
    func test_openInCairn_routesFilePasteboardToNewTab() {
        let url = tmp()
        let pb = NSPasteboard(name: NSPasteboard.Name("test-\(UUID().uuidString)"))
        pb.clearContents()
        pb.writeObjects([url as NSURL])

        assertProviderRoutes(pb, to: url)
    }

    func test_openInCairn_routesSingleFileURLStringToNewTab() {
        let url = tmp()
        let pb = NSPasteboard(name: NSPasteboard.Name("test-\(UUID().uuidString)"))
        pb.declareTypes([.fileURL], owner: nil)
        pb.setString(url.absoluteString, forType: .fileURL)

        assertProviderRoutes(pb, to: url)
    }

    func test_openInCairn_routesPlainTextFileURLToNewTab() {
        let url = tmp()
        let pb = NSPasteboard(name: NSPasteboard.Name("test-\(UUID().uuidString)"))
        pb.declareTypes([.string], owner: nil)
        pb.setString(url.absoluteString, forType: .string)

        assertProviderRoutes(pb, to: url)
    }

    private func assertProviderRoutes(_ pb: NSPasteboard, to url: URL, file: StaticString = #filePath, line: UInt = #line) {
        Tab.disableBackgroundServicesForTests = true
        defer {
            Tab.disableBackgroundServicesForTests = false
            CairnServicesProvider.shared.app = nil
        }

        let app = AppModel()
        let scene = WindowSceneModel(engine: app.engine, bookmarks: app.bookmarks, initialURL: url)
        app.register(scene: scene)
        CairnServicesProvider.shared.app = app

        var err: NSString = ""
        let countBefore = scene.tabs.count
        CairnServicesProvider.shared.openInCairn(pb, userData: "", error: &err)

        XCTAssertEqual(err, "", file: file, line: line)
        XCTAssertEqual(scene.tabs.count, countBefore + 1, file: file, line: line)
        XCTAssertEqual(scene.activeTab?.currentFolder?.standardizedFileURL.path, url.standardizedFileURL.path, file: file, line: line)
    }

    private func tmp() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CairnServicesProviderTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

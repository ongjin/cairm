import XCTest
@testable import Cairn

final class CairnURLRouterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Tab.disableBackgroundServicesForTests = true
    }

    override func tearDown() {
        Tab.disableBackgroundServicesForTests = false
        super.tearDown()
    }

    private func tmp() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CairnURLRouterTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func test_parse_localOpenURL() throws {
        let req = try CairnURLRouter.parse(URL(string: "cairn://open?path=/Users/me/work")!)
        switch req {
        case .openLocal(let url):
            XCTAssertEqual(url.path, "/Users/me/work")
        default:
            XCTFail("wrong case")
        }
    }

    func test_parse_remoteOpenURL() throws {
        let req = try CairnURLRouter.parse(URL(string: "cairn://remote?host=prod&path=/var/log")!)
        switch req {
        case .openRemote(let alias, let path):
            XCTAssertEqual(alias, "prod")
            XCTAssertEqual(path, "/var/log")
        default:
            XCTFail("wrong case")
        }
    }

    func test_parse_unknownHostReturnsMalformed() {
        XCTAssertThrowsError(try CairnURLRouter.parse(URL(string: "cairn://bogus?x=1")!))
    }

    func test_parse_missingPathOnOpenThrows() {
        XCTAssertThrowsError(try CairnURLRouter.parse(URL(string: "cairn://open")!))
    }

    func test_parse_percentEncodedPathDecoded() throws {
        let req = try CairnURLRouter.parse(URL(string: "cairn://open?path=/tmp/a%20b")!)
        if case .openLocal(let url) = req { XCTAssertEqual(url.path, "/tmp/a b") }
    }

    @MainActor
    func test_dispatch_openLocal_opensTabInActivePane() async {
        let url = tmp()
        let app = AppModel()
        let scene = WindowSceneModel(engine: app.engine, bookmarks: app.bookmarks, initialURL: url)
        let countBefore = scene.tabs.count
        CairnURLRouter.dispatch(.openLocal(url), in: app, activeScene: scene)
        XCTAssertEqual(scene.tabs.count, countBefore + 1)
    }
}

import XCTest
@testable import Cairn

final class CairnURLRouterTests: XCTestCase {
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
}

import XCTest
@testable import Cairn

final class ClipboardPasteServiceTests: XCTestCase {

    // MARK: - Fixture

    private var tmp: URL!

    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cairn-paste-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
        super.tearDown()
    }

    private func touch(_ name: String) {
        FileManager.default.createFile(atPath: tmp.appendingPathComponent(name).path,
                                       contents: Data())
    }

    // MARK: - uniqueDestination / appendCopy

    func test_uniqueDestination_appendCopy_noCollisionReturnsOriginal() {
        let url = ClipboardPasteService.uniqueDestination(
            filename: "foo.txt", in: tmp, rule: .appendCopy)
        XCTAssertEqual(url.lastPathComponent, "foo.txt")
    }

    func test_uniqueDestination_appendCopy_firstCollision() {
        touch("foo.txt")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "foo.txt", in: tmp, rule: .appendCopy)
        XCTAssertEqual(url.lastPathComponent, "foo copy.txt")
    }

    func test_uniqueDestination_appendCopy_secondCollision() {
        touch("foo.txt")
        touch("foo copy.txt")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "foo.txt", in: tmp, rule: .appendCopy)
        XCTAssertEqual(url.lastPathComponent, "foo copy 2.txt")
    }

    func test_uniqueDestination_appendCopy_thirdCollision() {
        touch("foo.txt")
        touch("foo copy.txt")
        touch("foo copy 2.txt")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "foo.txt", in: tmp, rule: .appendCopy)
        XCTAssertEqual(url.lastPathComponent, "foo copy 3.txt")
    }

    func test_uniqueDestination_appendCopy_dotfile() {
        touch(".gitignore")
        let url = ClipboardPasteService.uniqueDestination(
            filename: ".gitignore", in: tmp, rule: .appendCopy)
        // Leading-dot files have no "extension" in Finder's view.
        XCTAssertEqual(url.lastPathComponent, ".gitignore copy")
    }

    func test_uniqueDestination_appendCopy_compositeExtension() {
        touch("archive.tar.gz")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "archive.tar.gz", in: tmp, rule: .appendCopy)
        // Finder splits on the LAST dot only.
        XCTAssertEqual(url.lastPathComponent, "archive.tar copy.gz")
    }

    func test_uniqueDestination_appendCopy_noExtension() {
        touch("Makefile")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "Makefile", in: tmp, rule: .appendCopy)
        XCTAssertEqual(url.lastPathComponent, "Makefile copy")
    }

    // MARK: - uniqueDestination / appendNumber

    func test_uniqueDestination_appendNumber_noCollision() {
        let url = ClipboardPasteService.uniqueDestination(
            filename: "Untitled.png", in: tmp, rule: .appendNumber)
        XCTAssertEqual(url.lastPathComponent, "Untitled.png")
    }

    func test_uniqueDestination_appendNumber_firstCollision() {
        touch("Untitled.png")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "Untitled.png", in: tmp, rule: .appendNumber)
        XCTAssertEqual(url.lastPathComponent, "Untitled 2.png")
    }

    func test_uniqueDestination_appendNumber_secondCollision() {
        touch("Untitled.png")
        touch("Untitled 2.png")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "Untitled.png", in: tmp, rule: .appendNumber)
        XCTAssertEqual(url.lastPathComponent, "Untitled 3.png")
    }

    func test_uniqueDestination_appendNumber_differentExtDoesNotCollide() {
        touch("Untitled.png")
        let url = ClipboardPasteService.uniqueDestination(
            filename: "Untitled.jpg", in: tmp, rule: .appendNumber)
        XCTAssertEqual(url.lastPathComponent, "Untitled.jpg")
    }
}

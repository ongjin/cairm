import XCTest
import AppKit
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

    // MARK: - tiffToPng

    func test_tiffToPng_roundtripsThroughNSImage() {
        // 1×1 white pixel as TIFF. NSImage → tiffRepresentation is the simplest way.
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation else {
            return XCTFail("fixture: couldn't produce TIFF")
        }

        let png = ClipboardPasteService.tiffToPng(tiff)
        XCTAssertNotNil(png)
        XCTAssertGreaterThan(png?.count ?? 0, 0)
        // PNG magic number: 89 50 4E 47 0D 0A 1A 0A
        let expectedMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertEqual(Array(png!.prefix(8)), expectedMagic)
    }

    func test_tiffToPng_returnsNilForGarbage() {
        let garbage = Data([0x00, 0x01, 0x02])
        XCTAssertNil(ClipboardPasteService.tiffToPng(garbage))
    }

    // MARK: - read(from:)

    /// Allocates a fresh, uniquely-named pasteboard so tests don't clobber
    /// the user's real clipboard or race with each other.
    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("cairn.test.\(UUID().uuidString)"))
    }

    func test_read_emptyPasteboardReturnsNil() {
        let pb = scratchPasteboard()
        pb.clearContents()
        XCTAssertNil(ClipboardPasteService.read(from: pb))
    }

    func test_read_fileURLsWinOverImage() {
        let pb = scratchPasteboard()
        pb.clearContents()
        // Stage both kinds and assert file URLs take priority.
        let fileURL = tmp.appendingPathComponent("sample.txt")
        touch("sample.txt")
        pb.writeObjects([fileURL as NSURL])
        pb.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)

        guard case .files(let urls) = ClipboardPasteService.read(from: pb) else {
            return XCTFail("expected .files")
        }
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.lastPathComponent, "sample.txt")
    }

    func test_read_pngImageOnly() {
        let pb = scratchPasteboard()
        pb.clearContents()
        let fakePng = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
        pb.setData(fakePng, forType: .png)

        guard case .image(let data, let ext) = ClipboardPasteService.read(from: pb) else {
            return XCTFail("expected .image")
        }
        XCTAssertEqual(data, fakePng)
        XCTAssertEqual(ext, "png")
    }

    func test_read_tiffConvertsToPng() {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        img.unlockFocus()
        let tiff = img.tiffRepresentation!

        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setData(tiff, forType: .tiff)

        guard case .image(let data, let ext) = ClipboardPasteService.read(from: pb) else {
            return XCTFail("expected .image")
        }
        XCTAssertEqual(ext, "png")
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        XCTAssertEqual(Array(data.prefix(4)), pngMagic)
    }

    func test_read_jpegPassthrough() {
        let pb = scratchPasteboard()
        pb.clearContents()
        let fakeJpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])
        let jpegType = NSPasteboard.PasteboardType("public.jpeg")
        pb.setData(fakeJpeg, forType: jpegType)

        guard case .image(let data, let ext) = ClipboardPasteService.read(from: pb) else {
            return XCTFail("expected .image")
        }
        XCTAssertEqual(data, fakeJpeg)
        XCTAssertEqual(ext, "jpg")
    }
}

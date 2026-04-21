import XCTest
@testable import Cairn

final class PreviewModelTests: XCTestCase {
    func test_initial_state_is_idle() {
        let engine = CairnEngine()
        let model = PreviewModel(engine: engine)
        if case .idle = model.state {} else { XCTFail("initial state should be .idle") }
        XCTAssertNil(model.focus)
    }

    func test_focus_nil_clears_state_to_idle() async {
        let engine = CairnEngine()
        let model = PreviewModel(engine: engine)
        // Preload a focused URL → directory case.
        model.focus = FileManager.default.temporaryDirectory
        model.state = .directory(childCount: 5)
        model.focus = nil
        if case .idle = model.state {} else { XCTFail("nil focus should reset to .idle") }
    }

    func test_lru_caches_up_to_16_then_evicts_oldest() {
        let engine = CairnEngine()
        let model = PreviewModel(engine: engine)
        // Inject 17 arbitrary cached URLs — the first one should be evicted.
        for i in 0..<17 {
            let u = URL(fileURLWithPath: "/tmp/preview-\(i)")
            model.cache(state: .text("content-\(i)"), for: u)
        }
        XCTAssertNil(model.cached(for: URL(fileURLWithPath: "/tmp/preview-0")),
                     "oldest entry should have been evicted")
        XCTAssertNotNil(model.cached(for: URL(fileURLWithPath: "/tmp/preview-16")),
                        "newest entry should be present")
    }
}

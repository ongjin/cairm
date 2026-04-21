import Foundation
import Observation

/// Folder-scoped view model. One instance per currently-displayed folder.
@Observable
final class FolderModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var entries: [FileEntry] = []
    private(set) var state: LoadState = .idle

    private let engine: CairnEngine

    init(engine: CairnEngine) {
        self.engine = engine
    }

    /// Loads the folder. Caller must ensure security-scoped access is active.
    @MainActor
    func load(_ url: URL) async {
        state = .loading
        do {
            let list = try await engine.listDirectory(url)
            entries = list
            state = .loaded
        } catch {
            entries = []
            state = .failed(String(describing: error))
        }
    }

    func clear() {
        entries = []
        state = .idle
    }
}

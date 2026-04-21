import Foundation

/// Stack-based navigation history. `push` discards any forward entries past the
/// current index (Safari-style). Used by AppModel to drive ⌘←/⌘→.
struct NavigationHistory: Equatable {
    private(set) var stack: [URL] = []
    private(set) var index: Int = -1

    var current: URL? {
        guard index >= 0, index < stack.count else { return nil }
        return stack[index]
    }

    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index >= 0 && index < stack.count - 1 }

    mutating func push(_ url: URL) {
        // Truncate forward history when branching.
        if index < stack.count - 1 {
            stack.removeSubrange((index + 1)..<stack.count)
        }
        stack.append(url)
        index = stack.count - 1
    }

    @discardableResult
    mutating func goBack() -> URL? {
        guard canGoBack else { return nil }
        index -= 1
        return stack[index]
    }

    @discardableResult
    mutating func goForward() -> URL? {
        guard canGoForward else { return nil }
        index += 1
        return stack[index]
    }
}

import AppKit

enum HistoryNavigationAction: Equatable {
    case back
    case forward
}

enum HistoryNavigationRouting: Equatable {
    case passThrough
    case consume
    case navigate(HistoryNavigationAction)
}

final class HistoryNavigationInputRouter {
    static let leftArrowKeyCode: UInt16 = 123
    static let rightArrowKeyCode: UInt16 = 124

    private var handledMouseDownButtons = Set<Int>()

    func routeOtherMouseDown(buttonNumber: Int) -> HistoryNavigationRouting {
        guard let action = Self.action(forMouseButtonNumber: buttonNumber) else {
            return .passThrough
        }
        handledMouseDownButtons.insert(buttonNumber)
        return .navigate(action)
    }

    func routeOtherMouseUp(buttonNumber: Int) -> HistoryNavigationRouting {
        if handledMouseDownButtons.remove(buttonNumber) != nil {
            return .consume
        }
        guard let action = Self.action(forMouseButtonNumber: buttonNumber) else {
            return .passThrough
        }
        return .navigate(action)
    }

    static func routeKeyDown(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> HistoryNavigationRouting {
        let commandModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard modifiers.intersection(commandModifiers) == .command else {
            return .passThrough
        }

        switch keyCode {
        case leftArrowKeyCode:
            return .navigate(.back)
        case rightArrowKeyCode:
            return .navigate(.forward)
        default:
            return .passThrough
        }
    }

    private static func action(forMouseButtonNumber buttonNumber: Int) -> HistoryNavigationAction? {
        switch buttonNumber {
        case 3:
            return .back
        case 4:
            return .forward
        default:
            return nil
        }
    }
}

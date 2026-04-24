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
    static let auxMouseButtonsSubtype: Int16 = 7
    static let rightBracketKeyCode: UInt16 = 30
    static let leftBracketKeyCode: UInt16 = 33
    static let leftArrowKeyCode: UInt16 = 123
    static let rightArrowKeyCode: UInt16 = 124

    private var handledMouseDownButtons = Set<Int>()
    private var handledAuxMouseButtons = Set<Int>()

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

    func routeAuxMouseButtons(changedButtons: Int, pressedButtons: Int) -> HistoryNavigationRouting {
        for buttonNumber in [3, 4] {
            let buttonMask = 1 << buttonNumber
            guard changedButtons & buttonMask != 0 else { continue }
            guard let action = Self.action(forMouseButtonNumber: buttonNumber) else {
                return .passThrough
            }

            if pressedButtons & buttonMask != 0 {
                handledAuxMouseButtons.insert(buttonNumber)
                return .navigate(action)
            }
            if handledAuxMouseButtons.remove(buttonNumber) != nil {
                return .consume
            }
            return .navigate(action)
        }
        return .passThrough
    }

    static func routeKeyDown(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> HistoryNavigationRouting {
        let commandModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard modifiers.intersection(commandModifiers) == .command else {
            return .passThrough
        }

        switch keyCode {
        case leftArrowKeyCode, leftBracketKeyCode:
            return .navigate(.back)
        case rightArrowKeyCode, rightBracketKeyCode:
            return .navigate(.forward)
        default:
            return .passThrough
        }
    }

    static func routeSwipe(deltaX: CGFloat, deltaY: CGFloat) -> HistoryNavigationRouting {
        guard abs(deltaX) > abs(deltaY), deltaX != 0 else {
            return .passThrough
        }
        return deltaX < 0 ? .navigate(.forward) : .navigate(.back)
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

import Foundation
import Observation

/// Observable facade over UserDefaults for user-facing settings. Keys live
/// under `com.ongjin.cairn.settings.*` so they don't collide with other
/// AppStorage keys elsewhere.
@Observable
final class SettingsStore {
    enum StartFolder: String, CaseIterable, Identifiable {
        case lastUsed
        case home
        var id: String { rawValue }
        var label: String {
            switch self {
            case .lastUsed: return "Last used folder"
            case .home:     return "Home (~)"
            }
        }
    }

    enum SortField: String, CaseIterable, Identifiable {
        case name, size, modified
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum FontSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var pt: CGFloat {
            switch self {
            case .small: return 11
            case .medium: return 12
            case .large: return 14
            }
        }
    }

    private let defaults: UserDefaults

    var startFolder: StartFolder {
        didSet { defaults.set(startFolder.rawValue, forKey: Keys.startFolder) }
    }
    var restoreTabs: Bool {
        didSet { defaults.set(restoreTabs, forKey: Keys.restoreTabs) }
    }
    var fontSize: FontSize {
        didSet { defaults.set(fontSize.rawValue, forKey: Keys.fontSize) }
    }
    var defaultSortField: SortField {
        didSet { defaults.set(defaultSortField.rawValue, forKey: Keys.defaultSortField) }
    }
    var defaultSortAscending: Bool {
        didSet { defaults.set(defaultSortAscending, forKey: Keys.defaultSortAscending) }
    }
    var showHiddenByDefault: Bool {
        didSet { defaults.set(showHiddenByDefault, forKey: Keys.showHiddenByDefault) }
    }
    var showGitColumn: Bool {
        didSet { defaults.set(showGitColumn, forKey: Keys.showGitColumn) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.startFolder = StartFolder(rawValue: defaults.string(forKey: Keys.startFolder) ?? "") ?? .lastUsed
        self.restoreTabs = defaults.object(forKey: Keys.restoreTabs) as? Bool ?? true
        self.fontSize = FontSize(rawValue: defaults.string(forKey: Keys.fontSize) ?? "") ?? .medium
        self.defaultSortField = SortField(rawValue: defaults.string(forKey: Keys.defaultSortField) ?? "") ?? .name
        self.defaultSortAscending = defaults.object(forKey: Keys.defaultSortAscending) as? Bool ?? true
        self.showHiddenByDefault = defaults.bool(forKey: Keys.showHiddenByDefault)
        self.showGitColumn = defaults.object(forKey: Keys.showGitColumn) as? Bool ?? true
    }

    private enum Keys {
        static let startFolder           = "com.ongjin.cairn.settings.startFolder"
        static let restoreTabs           = "com.ongjin.cairn.settings.restoreTabs"
        static let fontSize              = "com.ongjin.cairn.settings.fontSize"
        static let defaultSortField      = "com.ongjin.cairn.settings.defaultSortField"
        static let defaultSortAscending  = "com.ongjin.cairn.settings.defaultSortAscending"
        static let showHiddenByDefault   = "com.ongjin.cairn.settings.showHiddenByDefault"
        static let showGitColumn         = "com.ongjin.cairn.settings.showGitColumn"
    }
}

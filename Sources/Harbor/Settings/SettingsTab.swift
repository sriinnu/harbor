import Foundation

/// The Settings window's tabs, in toolbar order (board item H-063).
enum SettingsTab: Hashable {
    case general
    case menu
    case repositories
    case accounts
    case localGit
    case about
    #if DEBUG
        case debug
    #endif
}

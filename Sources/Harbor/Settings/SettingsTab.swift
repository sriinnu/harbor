import Foundation

enum SettingsTab: Hashable {
    case general
    case repositories
    case accounts
    case advanced
    case credits
    case about
    #if DEBUG
        case debug
    #endif
}

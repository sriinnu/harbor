import Foundation

/// The global shortcut that opens and closes the panel. Stored as a virtual key code and a
/// Carbon modifier mask (the values `RegisterEventHotKey` takes), so the app can register it
/// as is. Off by default: a global combo is the user's to choose.
public struct HotkeySettings: Equatable, Codable, Sendable {
    /// Carbon modifier bits (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
    public enum Modifier {
        public static let command: UInt32 = 0x100
        public static let shift: UInt32 = 0x200
        public static let option: UInt32 = 0x800
        public static let control: UInt32 = 0x1000
    }

    public static let defaultKeyCode: UInt32 = 4 // H
    public static let defaultModifiers: UInt32 = Modifier.control | Modifier.option

    public var enabled: Bool = false
    public var keyCode: UInt32 = HotkeySettings.defaultKeyCode
    public var modifiers: UInt32 = HotkeySettings.defaultModifiers

    public init() {}

    public init(enabled: Bool, keyCode: UInt32, modifiers: UInt32) {
        self.enabled = enabled
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Settings saved before a field existed must still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.keyCode = try container.decodeIfPresent(UInt32.self, forKey: .keyCode) ?? Self.defaultKeyCode
        self.modifiers = try container.decodeIfPresent(UInt32.self, forKey: .modifiers) ?? Self.defaultModifiers
    }

    /// A global shortcut needs Command, Control or Option; Shift alone would eat typing.
    public static func isUsable(modifiers: UInt32) -> Bool {
        modifiers & (Modifier.command | Modifier.control | Modifier.option) != 0
    }

    public var isUsable: Bool { Self.isUsable(modifiers: self.modifiers) }

    public mutating func reset() {
        self.keyCode = Self.defaultKeyCode
        self.modifiers = Self.defaultModifiers
    }

    /// "⌃⌥H": modifiers in the order macOS writes them, then the key.
    public var display: String { Self.display(keyCode: self.keyCode, modifiers: self.modifiers) }

    public static func display(keyCode: UInt32, modifiers: UInt32) -> String {
        var text = ""
        if modifiers & Modifier.control != 0 { text += "⌃" }
        if modifiers & Modifier.option != 0 { text += "⌥" }
        if modifiers & Modifier.shift != 0 { text += "⇧" }
        if modifiers & Modifier.command != 0 { text += "⌘" }
        return text + (keyNames[keyCode] ?? "Key \(keyCode)")
    }

    /// What VoiceOver should say: "Control Option H".
    public var spokenDisplay: String {
        var words: [String] = []
        if self.modifiers & Modifier.control != 0 { words.append("Control") }
        if self.modifiers & Modifier.option != 0 { words.append("Option") }
        if self.modifiers & Modifier.shift != 0 { words.append("Shift") }
        if self.modifiers & Modifier.command != 0 { words.append("Command") }
        words.append(Self.spokenKeyNames[self.keyCode] ?? Self.keyNames[self.keyCode] ?? "key \(self.keyCode)")
        return words.joined(separator: " ")
    }

    private static let spokenKeyNames: [UInt32: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 123: "Left arrow", 124: "Right arrow",
        125: "Down arrow", 126: "Up arrow"
    ]

    private static let keyNames: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K",
        37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U",
        9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`"
    ]
}

import Foundation
import HarborCore
import Testing

@Suite("HotkeySettings")
struct HotkeySettingsTests {
    @Test("defaults: off, Control-Option-H")
    func defaults() {
        let hotkey = HotkeySettings()
        #expect(hotkey.enabled == false)
        #expect(hotkey.keyCode == 4)
        #expect(hotkey.modifiers == 0x1800)
        #expect(hotkey.display == "⌃⌥H")
        #expect(hotkey.spokenDisplay == "Control Option H")
    }

    @Test("round-trips through JSON")
    func roundTrip() throws {
        let saved = HotkeySettings(enabled: true, keyCode: 49, modifiers: HotkeySettings.Modifier.command | HotkeySettings.Modifier.shift)
        let back = try JSONDecoder().decode(HotkeySettings.self, from: JSONEncoder().encode(saved))
        #expect(back == saved)
        #expect(back.display == "⇧⌘Space")
    }

    @Test("a saved file without the fields decodes to the defaults")
    func missingFields() throws {
        let back = try JSONDecoder().decode(HotkeySettings.self, from: Data("{}".utf8))
        #expect(back == HotkeySettings())
        let partial = try JSONDecoder().decode(HotkeySettings.self, from: Data(#"{"enabled":true}"#.utf8))
        #expect(partial == HotkeySettings(enabled: true, keyCode: 4, modifiers: 0x1800))
    }

    @Test("settings saved before the hotkey existed still load whole")
    func oldSettingsFile() throws {
        var old = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(UserSettings())) as? [String: Any])
        old.removeValue(forKey: "hotkey")
        old["launchAtLogin"] = true
        let data = try JSONSerialization.data(withJSONObject: old)
        let loaded = try JSONDecoder().decode(UserSettings.self, from: data)
        #expect(loaded.hotkey == HotkeySettings())
        #expect(loaded.launchAtLogin == true)
        // Even a bare object loads, instead of throwing the file away.
        #expect(try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8)) == UserSettings())
    }

    @Test("a combo needs Command, Control or Option")
    func usable() {
        #expect(!HotkeySettings.isUsable(modifiers: 0))
        #expect(!HotkeySettings.isUsable(modifiers: HotkeySettings.Modifier.shift))
        #expect(HotkeySettings.isUsable(modifiers: HotkeySettings.Modifier.option))
        #expect(HotkeySettings(enabled: true, keyCode: 4, modifiers: 0x200).isUsable == false)
    }

    @Test("reset restores the combo and keeps the on/off choice")
    func reset() {
        var hotkey = HotkeySettings(enabled: true, keyCode: 0, modifiers: 0x100)
        hotkey.reset()
        #expect(hotkey == HotkeySettings(enabled: true, keyCode: 4, modifiers: 0x1800))
    }

    @Test("an unknown key falls back to its code")
    func unknownKey() {
        #expect(HotkeySettings.display(keyCode: 200, modifiers: 0x100) == "⌘Key 200")
    }
}

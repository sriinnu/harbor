import AppKit
import HarborCore
import SwiftUI

/// Settings > General > Shortcut: an on/off toggle and a recorder for the combo that opens and
/// closes the panel. The registration result is shown as it is, taken or not.
struct HotkeySettingsSection: View {
    @Bindable var session: Session
    let appState: AppState
    private let hotkey = GlobalHotkey.shared
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Section {
            Toggle(isOn: self.$session.settings.hotkey.enabled) {
                SettingsLabel(title: "Open Harbor with a shortcut", detail: "Works from any app. Needs no extra permission.")
            }
            .accessibilityLabel("Open Harbor with a global shortcut")
            .onChange(of: self.session.settings.hotkey.enabled) { _, _ in self.commit() }

            LabeledContent {
                HStack(spacing: 8) {
                    Button(self.isRecording ? "Type shortcut…" : self.session.settings.hotkey.display) {
                        self.isRecording ? self.stopRecording() : self.startRecording()
                    }
                    .accessibilityLabel("Shortcut")
                    .accessibilityValue(self.isRecording ? "Recording" : self.session.settings.hotkey.spokenDisplay)
                    .accessibilityHint(self.isRecording ? "Press the new key combination, or Escape to cancel" : "Activate, then press a new key combination")
                    Button("Reset") {
                        self.stopRecording()
                        self.session.settings.hotkey.reset()
                        self.commit()
                    }
                    .disabled(self.session.settings.hotkey == HotkeySettings(enabled: self.session.settings.hotkey.enabled, keyCode: HotkeySettings.defaultKeyCode, modifiers: HotkeySettings.defaultModifiers))
                    .accessibilityLabel("Reset shortcut to \(HotkeySettings().spokenDisplay)")
                }
            } label: {
                SettingsLabel(title: "Shortcut", detail: nil)
            }
            .disabled(!self.session.settings.hotkey.enabled)

            if let message = self.hotkey.status.message {
                SettingsStatus(text: message.text, kind: message.isProblem ? .warning : .ok)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Shortcut")
        } footer: {
            SettingsFooter("Include Command, Control or Option. Press Escape while recording to cancel.")
        }
        .onDisappear { self.stopRecording() }
    }

    private func commit() {
        self.appState.persistSettings()
        self.hotkey.apply(self.session.settings.hotkey)
    }

    private func startRecording() {
        self.isRecording = true
        self.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard self.isRecording else { return event }
            if event.keyCode == 53 { // Escape cancels
                self.stopRecording()
                return nil
            }
            let modifiers = Self.carbonModifiers(event.modifierFlags)
            guard HotkeySettings.isUsable(modifiers: modifiers) else {
                NSSound.beep()
                return nil
            }
            self.session.settings.hotkey.keyCode = UInt32(event.keyCode)
            self.session.settings.hotkey.modifiers = modifiers
            self.stopRecording()
            self.commit()
            return nil
        }
    }

    private func stopRecording() {
        self.isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        self.monitor = nil
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var bits: UInt32 = 0
        if flags.contains(.command) { bits |= HotkeySettings.Modifier.command }
        if flags.contains(.shift) { bits |= HotkeySettings.Modifier.shift }
        if flags.contains(.option) { bits |= HotkeySettings.Modifier.option }
        if flags.contains(.control) { bits |= HotkeySettings.Modifier.control }
        return bits
    }
}

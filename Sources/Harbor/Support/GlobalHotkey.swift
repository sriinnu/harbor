import Carbon.HIToolbox
import HarborCore
import Observation
import OSLog

/// Registers Harbor's one global shortcut with Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility permission and no entitlement. `apply` is the only entry point: it drops the
/// old registration before making a new one, and `shutdown` drops it on quit.
@MainActor
@Observable
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    enum Status: Equatable {
        case off
        case registered(String)
        /// Another app (or the system) already owns this combo.
        case taken(String)
        /// Carbon refused for another reason (the status code).
        case failed(OSStatus)
        case unusable
    }

    private(set) var status = Status.off
    @ObservationIgnored var onPress: (() -> Void)?
    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var handlerRef: EventHandlerRef?
    @ObservationIgnored private let logger = Logger(subsystem: "com.sriinnu.harbor", category: "hotkey")
    private static let signature: OSType = 0x4842_5248 // "HBRH"

    /// Registers `settings` (or nothing when it is off), replacing whatever was registered.
    func apply(_ settings: HotkeySettings) {
        self.unregister()
        guard settings.enabled else {
            self.status = .off
            return
        }
        guard settings.isUsable else {
            self.status = .unusable
            return
        }
        self.installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let result = RegisterEventHotKey(settings.keyCode, settings.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if result == noErr, let ref {
            self.hotKeyRef = ref
            self.status = .registered(settings.display)
        } else if result == OSStatus(eventHotKeyExistsErr) {
            self.logger.notice("hotkey \(settings.display, privacy: .public) is taken")
            self.status = .taken(settings.display)
        } else {
            self.logger.error("hotkey register failed status=\(result, privacy: .public)")
            self.status = .failed(result)
        }
    }

    /// Releases the combo and the event handler, on quit.
    func shutdown() {
        self.unregister()
        if let handlerRef = self.handlerRef { RemoveEventHandler(handlerRef) }
        self.handlerRef = nil
        self.status = .off
    }

    private func unregister() {
        if let hotKeyRef = self.hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        self.hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard self.handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var ref: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let got = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            guard got == noErr, id.signature == GlobalHotkey.signature else { return OSStatus(eventNotHandledErr) }
            // The application event target delivers on the main thread.
            DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotkey.shared.onPress?() } }
            return noErr
        }, 1, &spec, nil, &ref)
        if status == noErr { self.handlerRef = ref }
    }
}

extension GlobalHotkey.Status {
    /// What Settings says under the toggle; nil when there is nothing to add.
    var message: (text: String, isProblem: Bool)? {
        switch self {
        case .off: nil
        case let .registered(combo): ("\(combo) opens and closes Harbor.", false)
        case let .taken(combo): ("\(combo) is already taken by another app or by macOS. Pick a different shortcut.", true)
        case let .failed(code): ("macOS refused this shortcut (error \(code)). Pick a different one.", true)
        case .unusable: ("Add Command, Control or Option to the shortcut.", true)
        }
    }
}

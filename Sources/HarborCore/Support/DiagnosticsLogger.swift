import OSLog

/// Lightweight opt-in logger controlled by user settings.
public actor DiagnosticsLogger {
    public static let shared = DiagnosticsLogger()
    private var enabled = false
    private let log = Logger(subsystem: "com.sriinnu.athena.harbor", category: "diagnostics")

    public func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    public func message(_ text: String) {
        guard self.enabled else { return }
        self.log.info("\(text, privacy: .public)")
    }
}

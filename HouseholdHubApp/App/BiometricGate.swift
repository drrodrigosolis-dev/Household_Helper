import LocalAuthentication

/// The optional Face ID gate (spec §2.1, §7.11). Uses `.deviceOwnerAuthentication`, so the device passcode is the
/// fallback and a failed Face ID never locks the owner out of their own data.
enum BiometricGate {
    /// False when the device has no passcode (e.g. a fresh simulator); the switch is then unavailable.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// What the device will ask for, for labels.
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return String(localized: "Face ID")
        case .touchID: return String(localized: "Touch ID")
        case .opticID: return String(localized: "Optic ID")
        default: return String(localized: "Passcode")
        }
    }

    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

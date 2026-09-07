import ApplicationServices

/// AXPress acknowledges an action request, not the lifetime of its menu.
/// A timeout can arrive while the other app is opening or tracking that menu.
enum MenuBarPressResult: Equatable, Sendable {
    case accepted
    case unconfirmed
    case unavailable

    init(error: AXError) {
        switch error {
        case .success:
            self = .accepted
        case .invalidUIElement, .actionUnsupported, .apiDisabled, .illegalArgument, .notImplemented:
            self = .unavailable
        default:
            // In particular, cannotComplete and generic failure do not prove
            // that the remote app rejected or failed to perform the request.
            self = .unconfirmed
        }
    }
}

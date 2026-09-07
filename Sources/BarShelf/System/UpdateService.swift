import Combine

/// The personal fork updates through reviewed source changes, never through the
/// upstream app's update feed. Keeping this service preserves the existing UI
/// integration points while making all upstream update controls disappear.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published private(set) var pendingVersion: String?
    var onWillShowWindow: (@MainActor () -> Void)?
    let isConfigured = false
    let canCheckForUpdates = false

    private init() {}

    func checkForUpdates() {}
}

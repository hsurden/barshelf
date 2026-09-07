import Combine
import Foundation

@MainActor
final class StateStore: ObservableObject {
    @Published private(set) var document: BarShelfDocument
    @Published private(set) var lastError: String?

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL? = nil) {
        let folder = baseURL ?? Self.applicationSupportFolder()

        fileURL = folder.appendingPathComponent("state.json")
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? decoder.decode(BarShelfDocument.self, from: data) {
            document = saved
        } else {
            document = BarShelfDocument()
        }
    }

    /// The app was renamed from Barkeep HS. On the first launch under the
    /// new name, the old state folder is copied (not moved) so a downgrade
    /// still finds its file. Nothing else is touched.
    private static func applicationSupportFolder() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("BarShelf", isDirectory: true)
        let legacy = support.appendingPathComponent("Barkeep", isDirectory: true)
        let manager = FileManager.default
        if !manager.fileExists(atPath: folder.path), manager.fileExists(atPath: legacy.path) {
            try? manager.copyItem(at: legacy, to: folder)
        }
        return folder
    }

    var settings: BarShelfSettings { document.settings }
    var rules: [String: ItemRule] { document.rules }

    /// Re-key rules and priority entries created by the earlier label-based
    /// scanner. This runs only with live evidence, because old documents do
    /// not contain enough information to migrate safely at decode time.
    func reconcileItemIdentities(with items: [MenuBarItemSnapshot]) {
        var updated = document
        var changed = false
        var availableRuleKeys = Set(updated.rules.keys)

        for item in items {
            if var direct = updated.rules[item.id] {
                if direct.displayName != item.displayName || direct.ownerName != item.ownerName {
                    direct.displayName = item.displayName
                    direct.ownerName = item.ownerName
                    updated.rules[item.id] = direct
                    changed = true
                }
                availableRuleKeys.remove(item.id)
                continue
            }

            let candidates = availableRuleKeys.compactMap { key -> (String, ItemRule)? in
                guard let rule = updated.rules[key], rule.bundleIdentifier == item.bundleIdentifier else {
                    return nil
                }
                return (key, rule)
            }
            let exact = candidates.filter {
                $0.1.displayName == item.displayName && $0.1.ownerName == item.ownerName
            }
            let legacyAXKey = item.sourceIdentifier.map {
                "\(item.bundleIdentifier ?? "pid:\(item.ownerPID)")|\($0)"
            }
            let identifierMatch = candidates.first { $0.0 == legacyAXKey }
            let sameOwner = candidates.filter { $0.1.ownerName == item.ownerName }
            let match: (String, ItemRule)?
            if let identifierMatch {
                match = identifierMatch
            } else if exact.count == 1 {
                match = exact[0]
            } else if sameOwner.count == 1,
                      items.filter({ $0.bundleIdentifier == item.bundleIdentifier }).count == 1 {
                match = sameOwner[0]
            } else {
                match = nil
            }
            guard let (oldKey, oldRule) = match else { continue }
            updated.rules[oldKey] = nil
            updated.rules[item.id] = ItemRule(
                id: item.id,
                displayName: item.displayName,
                ownerName: item.ownerName,
                bundleIdentifier: item.bundleIdentifier,
                zone: oldRule.zone,
                group: oldRule.group
            )
            availableRuleKeys.remove(oldKey)
            changed = true
        }

        if var priority = updated.priorityOrder {
            var usedOldIDs = Set<String>()
            for index in priority.indices {
                guard !items.contains(where: { $0.id == priority[index].id }) else { continue }
                let entry = priority[index]
                let candidates = items.filter {
                    $0.bundleIdentifier == entry.bundleIdentifier && !usedOldIDs.contains($0.id)
                }
                let exact = candidates.filter {
                    $0.displayName == entry.displayName && $0.ownerName == entry.ownerName
                }
                let legacyIdentifier = entry.id.split(separator: "|", maxSplits: 1)
                    .dropFirst().first.map(String.init)
                let identifierMatch = candidates.first { $0.sourceIdentifier == legacyIdentifier }
                let match = identifierMatch ?? (
                    exact.count == 1 ? exact[0] : (candidates.count == 1 ? candidates[0] : nil)
                )
                guard let match else { continue }
                priority[index] = PriorityEntry(
                    id: match.id,
                    displayName: match.displayName,
                    ownerName: match.ownerName,
                    bundleIdentifier: match.bundleIdentifier
                )
                usedOldIDs.insert(match.id)
                changed = true
            }
            updated.priorityOrder = priority
        }

        if updated.identityVersion != MenuBarItemIdentity.currentVersion {
            updated.identityVersion = MenuBarItemIdentity.currentVersion
            changed = true
        }
        guard changed else { return }
        document = updated
        save()
    }

    func updateSettings(_ change: (inout BarShelfSettings) -> Void) {
        var updated = document
        change(&updated.settings)
        document = updated
        save()
    }

    func setRule(for item: MenuBarItemSnapshot, zone: VisibilityZone) {
        var updated = document
        updated.rules[item.id] = ItemRule(
            id: item.id,
            displayName: item.displayName,
            ownerName: item.ownerName,
            bundleIdentifier: item.bundleIdentifier,
            zone: zone,
            group: document.rules[item.id]?.group
        )
        document = updated
        save()
    }

    var priorityOrder: [PriorityEntry] { document.priorityOrder ?? [] }

    func addPriority(for item: MenuBarItemSnapshot) {
        var updated = document
        var order = updated.priorityOrder ?? []
        guard !order.contains(where: { $0.id == item.id }) else { return }
        order.append(PriorityEntry(
            id: item.id,
            displayName: item.displayName,
            ownerName: item.ownerName,
            bundleIdentifier: item.bundleIdentifier
        ))
        updated.priorityOrder = order
        document = updated
        save()
    }

    func removePriority(id: String) {
        var updated = document
        updated.priorityOrder = (updated.priorityOrder ?? []).filter { $0.id != id }
        document = updated
        save()
    }

    func movePriority(fromOffsets: IndexSet, toOffset: Int) {
        var updated = document
        var order = updated.priorityOrder ?? []
        order.move(fromOffsets: fromOffsets, toOffset: toOffset)
        updated.priorityOrder = order
        document = updated
        save()
    }

    func removeRule(id: String) {
        var updated = document
        updated.rules[id] = nil
        document = updated
        save()
    }

    func saveProfile(named name: String) {
        var updated = document
        updated.profiles.append(
            BarShelfProfile(name: name, rules: document.rules, settings: document.settings)
        )
        document = updated
        save()
    }

    func loadProfile(id: UUID) {
        guard let profile = document.profiles.first(where: { $0.id == id }) else { return }
        var updated = document
        updated.rules = profile.rules
        updated.settings = profile.settings
        document = updated
        save()
    }

    func deleteProfile(id: UUID) {
        var updated = document
        updated.profiles.removeAll { $0.id == id }
        document = updated
        save()
    }

    func exportData() throws -> Data {
        try encoder.encode(document)
    }

    func importData(_ data: Data) throws {
        let imported = try decoder.decode(BarShelfDocument.self, from: data)
        guard imported.version == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        document = imported
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(document)
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var coordinator: AppCoordinator
    @ObservedObject private var store: StateStore

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        store = coordinator.store
    }

    var body: some View {
        TabView {
            ItemsSettingsView(coordinator: coordinator)
                .tabItem { Label("Items", systemImage: "menubar.rectangle") }
            BehaviorSettingsView(coordinator: coordinator)
                .tabItem { Label("Behavior", systemImage: "switch.2") }
            AppearanceSettingsView(coordinator: coordinator)
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
            AdvancedSettingsView(coordinator: coordinator)
                .tabItem { Label("Advanced", systemImage: "gearshape") }
        }
        .padding(12)
        .frame(minWidth: 760, minHeight: 500)
        .overlay(alignment: .bottom) {
            if let message = coordinator.message ?? store.lastError {
                Text(message)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
            }
        }
    }
}

private struct ItemsSettingsView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Menu bar items")
                        .font(.title2.weight(.semibold))
                    Text("Drag to reorder the bar. Use an item's menu to hide or unhide it.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if coordinator.isScanning || coordinator.isApplyingOrder {
                    ProgressView().controlSize(.small)
                }
                Button("Refresh") {
                    Task { await coordinator.refreshItems(promptForPermission: true) }
                }
                .disabled(coordinator.isScanning || coordinator.movingItemID != nil)
                if coordinator.pendingHideCount > 0 {
                    Button("Reapply Hidden Items") {
                        Task { await coordinator.reapplyHiddenItems() }
                    }
                    .disabled(
                        coordinator.isScanning ||
                        coordinator.isApplyingOrder ||
                        coordinator.movingItemID != nil
                    )
                    .help("Retry hiding the items macOS put back into the bar")
                }
            }

            if !AccessibilityPermission.isGranted {
                HStack {
                    Image(systemName: "hand.raised.fill")
                    Text("Accessibility is needed to list and move menu bar items.")
                    Spacer()
                    Button("Set Up Accessibility") { AccessibilityPermission.request() }
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(VisibilityZone.allCases) { zone in
                    ZoneColumn(zone: zone, coordinator: coordinator)
                }
            }
        }
        .padding(12)
        .task {
            if coordinator.items.isEmpty {
                await coordinator.refreshItems(promptForPermission: false)
            }
        }
    }
}

private struct ZoneColumn: View {
    let zone: VisibilityZone
    @ObservedObject var coordinator: AppCoordinator

    private var zoneItems: [MenuBarItemSnapshot] {
        coordinator.itemsForSettings(in: zone)
    }

    /// The in-bar column reorders the real bar by drag.
    private var isReorderColumn: Bool { zone == .alwaysVisible }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(zone.title)
                    .font(.headline)
                Spacer()
                Text("\(zoneItems.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(zone.help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 34, alignment: .topLeading)
            Divider()
            if isReorderColumn {
                List {
                    ForEach(zoneItems) { item in
                        ItemRow(item: item, coordinator: coordinator)
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { offsets, destination in
                        guard let sourceOffset = offsets.first else { return }
                        let moved = zoneItems[sourceOffset]
                        var reordered = zoneItems
                        reordered.move(fromOffsets: offsets, toOffset: destination)
                        guard let rank = reordered.firstIndex(of: moved),
                              rank != sourceOffset else { return }
                        Task { await coordinator.reorderItem(moved, toRank: rank) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(zoneItems) { item in
                            ItemRow(item: item, coordinator: coordinator)
                        }
                        if zoneItems.isEmpty {
                            Text("Nothing is hidden")
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { identifiers, _ in
            guard !coordinator.isScanning,
                  coordinator.movingItemID == nil,
                  let id = identifiers.first,
                  let item = coordinator.items.first(where: { $0.id == id }) else {
                return false
            }
            Task { await coordinator.moveItem(item, to: zone) }
            return true
        }
    }

}

private struct ItemRow: View {
    let item: MenuBarItemSnapshot
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(bundleIdentifier: item.bundleIdentifier)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .lineLimit(1)
                if item.ownerName != item.displayName {
                    Text(item.ownerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if coordinator.isPendingHide(item) {
                Text("still visible")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("macOS put this item back in the bar. Use Reapply Hidden Items to retry.")
            }
            Spacer(minLength: 2)
            if coordinator.movingItemID == item.id {
                ProgressView().controlSize(.small)
            } else {
                Menu {
                    ForEach(VisibilityZone.allCases) { zone in
                        Button(zone.title) {
                            Task { await coordinator.moveItem(item, to: zone) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(7)
        .background(.background, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .draggable(item.id)
        .disabled(coordinator.isScanning || coordinator.movingItemID != nil)
    }
}

private struct AppIcon: View {
    let bundleIdentifier: String?

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 22, height: 22)
        }
    }

    private var image: NSImage? {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct BehaviorSettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var store: StateStore

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        store = coordinator.store
    }

    var body: some View {
        Form {
            Section("Privacy") {
                SettingsToggle(
                    "Use Touch ID or the Mac password before reveal",
                    isOn: setting(\.requireAuthentication)
                )
            }
            Section("App") {
                SettingsToggle("Start Barkeep at login", isOn: setting(\.launchAtLogin))
                SettingsToggle("Show Barkeep in the Dock", isOn: setting(\.showDockIcon))
                HStack {
                    Text("Stop Barkeep and remove its menu bar controls until it is opened again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 16)
                    Button("Quit Barkeep HS", role: .destructive) {
                        coordinator.quitApp()
                    }
                }
            }
            Section("Keyboard shortcuts") {
                LabeledContent("Open or close the shelf", value: "⌘\\")
                LabeledContent("Open item picker", value: "⌘⇧Space")
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<BarkeepSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { value in
                store.updateSettings { $0[keyPath: keyPath] = value }
                coordinator.settingsDidChange()
            }
        )
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var store: StateStore

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        store = coordinator.store
    }

    var body: some View {
        Form {
            Section("Barkeep icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach(BarkeepIconStyle.allCases) { style in
                        Button {
                            store.updateSettings { $0.iconStyle = style }
                            coordinator.iconStyleDidChange()
                        } label: {
                            VStack(spacing: 6) {
                                Image(nsImage: BarkeepIconFactory.image(for: style, expanded: false))
                                    .resizable()
                                    .frame(width: 22, height: 22)
                                Text(style.title).font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(
                                store.settings.iconStyle == style ? Color.accentColor.opacity(0.18) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section("Item spacing") {
                SettingsToggle(
                    "Use tighter menu bar item spacing",
                    isOn: setting(\.reduceItemSpacing)
                )
                if store.settings.reduceItemSpacing {
                    LabeledContent("Spacing") {
                        Stepper("\(store.settings.itemSpacing)", value: setting(\.itemSpacing), in: 0...12)
                    }
                    LabeledContent("Padding") {
                        Stepper("\(store.settings.itemPadding)", value: setting(\.itemPadding), in: 0...12)
                    }
                }
                Text("A spacing change takes effect after you log out and log in. Barkeep restores the old values when you turn this off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<BarkeepSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { value in
                store.updateSettings { $0[keyPath: keyPath] = value }
                coordinator.settingsDidChange()
            }
        )
    }
}

private struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 16)
                switchControl
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var switchControl: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.28))
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                .padding(2)
        }
        .frame(width: 38, height: 22)
        .animation(.easeOut(duration: 0.12), value: isOn)
    }
}

private struct AdvancedSettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var store: StateStore
    @State private var profileName = ""

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        store = coordinator.store
    }

    var body: some View {
        Form {
            Section("Profiles") {
                HStack {
                    TextField("Profile name", text: $profileName)
                    Button("Save Current Setup") {
                        let name = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        store.saveProfile(named: name)
                        profileName = ""
                    }
                    .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(store.document.profiles) { profile in
                    HStack {
                        Text(profile.name)
                        Spacer()
                        Button("Load") {
                            store.loadProfile(id: profile.id)
                            coordinator.settingsDidChange()
                        }
                        Button(role: .destructive) {
                            store.deleteProfile(id: profile.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            Section("Backup") {
                HStack {
                    Button("Export Settings…") { coordinator.exportSettings() }
                    Button("Import Settings…") { coordinator.importSettings() }
                }
            }
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    HStack {
                        Text(AccessibilityPermission.isGranted ? "Allowed" : "Not allowed")
                            .foregroundStyle(AccessibilityPermission.isGranted ? .green : .secondary)
                        Button("Set Up") { AccessibilityPermission.request() }
                    }
                }
            }
            if coordinator.updater.isConfigured {
                UpdateSettingsView(updater: coordinator.updater)
            }
            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("License", value: "MIT")
                Text("Barkeep stores settings on this Mac. It sends no analytics and does not use Screen Recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return [version, build.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
    }
}

private struct UpdateSettingsView: View {
    @ObservedObject var updater: UpdateService

    var body: some View {
        Section("Updates") {
            HStack {
                Text(updater.pendingVersion.map { "Version \($0) is ready." } ?? "Barkeep checks once a day.")
                Spacer()
                Button(updater.pendingVersion.map { "Update to \($0)" } ?? "Check Now") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
            Text("Scheduled checks stay quiet until you open Barkeep.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

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
    @State private var selectedID: String?

    private var selectedItem: MenuBarItemSnapshot? {
        coordinator.items.first { $0.id == selectedID }
    }

    private var busy: Bool {
        coordinator.isScanning || coordinator.isApplyingOrder || coordinator.movingItemID != nil
    }

    private func canMove(to zone: VisibilityZone) -> Bool {
        guard !busy, let item = selectedItem, !item.isPinnedByMacOS else { return false }
        return coordinator.isOutOfBar(item) == (zone == .alwaysVisible)
    }

    private func moveSelected(to zone: VisibilityZone) {
        guard let item = selectedItem, canMove(to: zone) else { return }
        Task { await coordinator.moveItem(item, to: zone) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Menu bar items")
                        .font(.title2.weight(.semibold))
                    Text("Select an item and use the arrows, or drag it between the lists.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if coordinator.isScanning || coordinator.isApplyingOrder {
                    ProgressView().controlSize(.small)
                }
                Button(coordinator.canReturnTemporaryItem ? "Return Icon" : "Open Shelf") {
                    if coordinator.canReturnTemporaryItem {
                        coordinator.returnTemporaryItem()
                    } else {
                        coordinator.showShelf()
                    }
                }
                .disabled(busy)
                Button("Refresh") {
                    Task { await coordinator.refreshItems(promptForPermission: true) }
                }
                .disabled(coordinator.isScanning || coordinator.movingItemID != nil)
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

            HStack(alignment: .top, spacing: 8) {
                ZoneColumn(zone: .alwaysVisible, coordinator: coordinator, selectedID: $selectedID)
                VStack(spacing: 10) {
                    Button {
                        moveSelected(to: .alwaysHidden)
                    } label: {
                        Image(systemName: "arrow.right")
                            .frame(width: 20)
                    }
                    .disabled(!canMove(to: .alwaysHidden))
                    .help("Hide the selected item")
                    Button {
                        moveSelected(to: .alwaysVisible)
                    } label: {
                        Image(systemName: "arrow.left")
                            .frame(width: 20)
                    }
                    .disabled(!canMove(to: .alwaysVisible))
                    .help("Put the selected item back in the menu bar")
                }
                .padding(.top, 120)
                ZoneColumn(zone: .alwaysHidden, coordinator: coordinator, selectedID: $selectedID)
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
    @Binding var selectedID: String?

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
                        ItemRow(item: item, coordinator: coordinator, selectedID: $selectedID)
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
                            ItemRow(item: item, coordinator: coordinator, selectedID: $selectedID)
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
                  let item = coordinator.items.first(where: { $0.id == id }),
                  coordinator.isOutOfBar(item) != (zone == .alwaysHidden) else {
                return false
            }
            selectedID = item.id
            Task { await coordinator.moveItem(item, to: zone) }
            return true
        }
    }
}

private struct ItemRow: View {
    let item: MenuBarItemSnapshot
    @ObservedObject var coordinator: AppCoordinator
    @Binding var selectedID: String?

    private var isSelected: Bool { selectedID == item.id }

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(bundleIdentifier: item.bundleIdentifier)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .lineLimit(1)
                if item.ownerName != item.displayName {
                    Text(item.ownerName)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            if coordinator.movingItemID == item.id {
                ProgressView().controlSize(.small)
            }
        }
        .padding(7)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(
            isSelected ? Color.accentColor : Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedID = item.id }
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
                SettingsToggle("Start BarShelf at login", isOn: setting(\.launchAtLogin))
                SettingsToggle("Show BarShelf in the Dock", isOn: setting(\.showDockIcon))
                HStack {
                    Text("Stop BarShelf and remove its menu bar controls until it is opened again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 16)
                    Button("Quit BarShelf", role: .destructive) {
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

    private func setting<Value>(_ keyPath: WritableKeyPath<BarShelfSettings, Value>) -> Binding<Value> {
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
            Section("BarShelf icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach(BarShelfIconStyle.allCases) { style in
                        Button {
                            store.updateSettings { $0.iconStyle = style }
                            coordinator.iconStyleDidChange()
                        } label: {
                            VStack(spacing: 6) {
                                Image(nsImage: BarShelfIconFactory.image(for: style, expanded: false))
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
                Text("A spacing change takes effect after you log out and log in. BarShelf restores the old values when you turn this off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<BarShelfSettings, Value>) -> Binding<Value> {
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
                Text("BarShelf stores settings on this Mac. It sends no analytics and does not use Screen Recording.")
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
                Text(updater.pendingVersion.map { "Version \($0) is ready." } ?? "BarShelf checks once a day.")
                Spacer()
                Button(updater.pendingVersion.map { "Update to \($0)" } ?? "Check Now") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
            Text("Scheduled checks stay quiet until you open BarShelf.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

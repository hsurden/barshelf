import AppKit
import SwiftUI

struct SearchPanelView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var isShelfMode: Bool { coordinator.menuBarMode == .overflowShelf }

    private var contents: MenuBarPickerContents {
        if isShelfMode {
            // Nothing is deliberately hidden in shelf mode; the first section
            // is the set of items macOS pushed behind the notch or off screen.
            MenuBarPickerContents(items: coordinator.items, query: query) {
                coordinator.isOverflowed($0) ? .hidden : .alwaysVisible
            }
        } else {
            MenuBarPickerContents(items: coordinator.items, query: query) {
                coordinator.currentZone(for: $0)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Menu Bar Items")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await coordinator.refreshItems(promptForPermission: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh menu bar items")
                .disabled(coordinator.isScanning)
                Button {
                    coordinator.showSettingsFromPicker()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Open Barkeep settings")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter items", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if coordinator.isScanning {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)

            Divider()

            if !AccessibilityPermission.isGranted {
                VStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("Allow Accessibility to list and open menu bar items.")
                        .multilineTextAlignment(.center)
                    Button("Set Up Accessibility") {
                        AccessibilityPermission.request()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else {
                List {
                    if !contents.overflow.isEmpty {
                        Section("Hidden & Overflow") {
                            ForEach(contents.overflow) { item in
                                PickerItemRow(item: item, coordinator: coordinator)
                            }
                        }
                    }
                    if !contents.visible.isEmpty {
                        Section("Visible") {
                            ForEach(contents.visible) { item in
                                PickerItemRow(item: item, coordinator: coordinator)
                            }
                        }
                    }
                }
                .listStyle(.inset)

                if contents.isEmpty && !coordinator.isScanning {
                    Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "No menu bar items found"
                         : "No matching items")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
        .frame(minWidth: 400, minHeight: 420)
        .onAppear {
            if !coordinator.pendingSearchQuery.isEmpty {
                query = coordinator.pendingSearchQuery
                coordinator.pendingSearchQuery = ""
            }
            searchFocused = true
        }
    }
}

private struct PickerItemRow: View {
    let item: MenuBarItemSnapshot
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Button {
            Task { await coordinator.activate(item) }
        } label: {
            HStack(spacing: 10) {
                AppIconForSearch(bundleIdentifier: item.bundleIdentifier)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName)
                    if item.ownerName != item.displayName {
                        Text(item.ownerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
    }
}

private struct AppIconForSearch: View {
    let bundleIdentifier: String?

    var body: some View {
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "app.dashed")
                .frame(width: 24, height: 24)
        }
    }
}

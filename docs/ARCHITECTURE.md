# Barkeep architecture

Barkeep is one native macOS process. AppKit owns the application lifecycle, status items, panels,
global input, and macOS services. SwiftUI draws the settings, search, and permission views.

## Source map

```text
Sources/Barkeep/App/             lifecycle and AppCoordinator
Sources/Barkeep/Models/          saved and runtime state types
Sources/Barkeep/StatusBar/       three status items and icon rendering
Sources/Barkeep/Accessibility/   permission checks, scans, and item moves
Sources/Barkeep/Permissions/     guided Accessibility setup
Sources/Barkeep/Storage/         versioned local JSON storage
Sources/Barkeep/System/          hotkeys, triggers, login, spacing, and update policy
Sources/Barkeep/UI/              settings and search windows
Tests/BarkeepTests/              unit tests
scripts/                         build, install, DMG, and release tools
```

## Runtime components

| Component | Job | Runs outside the main actor? | Can post input? |
|---|---|---:|---:|
| `AppCoordinator` | Connect user actions, state, windows, and services | No | No |
| `StatusBarEngine` | Own the control item and two section boundaries | No | No |
| `AccessibilityScanner` | Read and press current menu bar items | Yes, on one serial queue | Press only |
| `ItemMoveService` | Validate and post one confirmed Command-drag | Yes, on one serial queue | Yes |
| `PermissionAssistant` | Open and follow the Accessibility settings window | No | No |
| `StateStore` | Load and save the versioned JSON document | No | No |
| `TriggerCenter` | Own optional reveal and hide event sources | No | No |
| `HotKeyCenter` | Register the two global keyboard shortcuts | No | No |
| `MenuBarSpacingService` | Apply and restore macOS spacing preferences | No | No |
| `UpdateService` | Disable upstream binary updates for this personal fork | No | No |

`AppCoordinator` is the only object that joins these parts. Views call coordinator methods. They
do not scan the menu bar or post input themselves.

## Visibility has three states

`StatusBarEngine.State` has three values.

| State | Hidden section | Always hidden section |
|---|---|---|
| `hidden` | Closed | Closed |
| `revealed` | Open | Closed |
| `revealedAll` | Open | Open |

The engine uses two large status item lengths as section boundaries. The control item stays to the
right. macOS keeps each status item's preferred position through its autosave name.

All clicks, hotkeys, triggers, picker actions, and menu commands call the coordinator. A normal
control-item click opens the picker; Option-click and explicit reveal commands still use the shared
authentication and auto-hide path.

## A safe item move has one fixed flow

1. The user selects a new section for one item.
2. The coordinator opens both sections.
3. The scanner reads the live menu bar.
4. The coordinator matches the selected item to the fresh result.
5. The status bar engine gives the target point for the requested section.
6. `ItemMoveService` validates the source frame, target point, and screen.
7. The service posts one Command-drag and returns the pointer to its old position.
8. The scanner reads the live menu bar again.
9. The store saves the rule only when the boundary frames confirm the new section.
10. The coordinator restores the earlier reveal state.

There can be only one move at a time. A failed validation or failed confirmation leaves the saved
rule unchanged.

## Geometry is temporary evidence

A menu bar item frame is valid only for the scan that returned it. Saved state contains no screen
coordinates and no Accessibility objects.

The move service rejects empty or very large source frames. Both endpoints must be on a current
screen. macOS owns menu bar overflow around a camera notch, so Barkeep does not reject a move just
because the cursor path crosses the center of a notched display. The second scan remains the source
of truth for whether the item landed.

## Background work stops when it is not needed

The scanner does not poll. Settings and search ask for a scan when they need current items. The
scanner uses one serial queue because Accessibility calls can block.

Opening the shelf creates one immutable membership snapshot from the union of saved Always hidden
intent and current physical overflow. Later geometry changes do not remove buttons during that
shelf session. Item labels remain live display data; persistence uses an Accessibility identifier
or a per-owner slot and migrates older label-based keys after a matching scan.

Shelf activation follows one serialized lifecycle: resting, shelf open, revealing the selected
item, manual interaction, and restoring. The selected item remains physically available without a
timer, including after its native menu or popover closes. A global Escape monitor or another normal
click on Barkeep explicitly ends the session and restores the hidden layout.

`TriggerCenter` creates only the event sources required by enabled settings.

- Hover uses a 10 Hz timer while hover reveal is on.
- Click and scroll use one global event monitor when either action is on.
- App-change hide uses one workspace observer.
- External-display reveal uses one screen observer.

Each settings update stops all old sources before it installs the new set.

## Local state uses one versioned document

`StateStore` writes this file with an atomic replace.

```text
~/Library/Application Support/Barkeep/state.json
```

`BarkeepDocument` contains its format version, settings, item rules, group names, and profiles.
JSON dates use ISO 8601. Import rejects a document with an unknown version.

Menu bar frames and Accessibility elements stay in memory. They are never written to disk.

## Permissions and system changes are narrow

- Accessibility is required to list, open, and move other apps' status items.
- Touch ID or the Mac password is used only when reveal protection is on.
- Launch at Login is optional and uses the main app service.
- Tighter spacing changes two user-level macOS preferences. Barkeep records the old values and
  restores them when the setting is off.
- Screen Recording is not used.
- The core app needs no network access.

## Updates cannot overwrite the personal fork

The app target does not link an automatic updater. `UpdateService` is a disabled compatibility shim
so upstream binaries cannot overwrite customized behavior. Upstream changes are fetched and
reviewed as source. Any future public release path needs its own identity and signing design.

## Tests cover stable logic and launch safety

The unit target checks boundary classification, product defaults, state persistence, observation,
and icon rendering. CI also builds the app, verifies the signature, and confirms that the process
stays open after launch.

Real menu bar moves need a signed app and Accessibility access. Test them manually with the same
app archive that will ship. Source-only tests cannot prove that macOS completed a move.

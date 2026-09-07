# BarShelf architecture

BarShelf is one native macOS process. AppKit owns the application lifecycle, status items, panels,
global input, and macOS services. SwiftUI draws the settings, search, and permission views.

## Source map

```text
Sources/BarShelf/App/             lifecycle and AppCoordinator
Sources/BarShelf/Models/          saved and runtime state types
Sources/BarShelf/StatusBar/       two status items and icon rendering
Sources/BarShelf/Accessibility/   permission checks, scans, and item moves
Sources/BarShelf/Permissions/     guided Accessibility setup
Sources/BarShelf/Storage/         versioned local JSON storage
Sources/BarShelf/System/          hotkeys, login, spacing, and update policy
Sources/BarShelf/UI/              settings and search windows
Tests/BarShelfTests/              unit tests
scripts/                         build, install, DMG, and release tools
```

## Runtime components

| Component | Job | Runs outside the main actor? | Can post input? |
|---|---|---:|---:|
| `AppCoordinator` | Connect user actions, state, windows, and services | No | No |
| `StatusBarEngine` | Own the control item and the Always hidden boundary | No | No |
| `AccessibilityScanner` | Read and press current menu bar items | Yes, on one serial queue | Press only |
| `ItemMoveService` | Validate and post one confirmed Command-drag | Yes, on one serial queue | Yes |
| `PermissionAssistant` | Open and follow the Accessibility settings window | No | No |
| `StateStore` | Load and save the versioned JSON document | No | No |
| `HotKeyCenter` | Register the two global keyboard shortcuts | No | No |
| `MenuBarSpacingService` | Apply and restore macOS spacing preferences | No | No |
| `UpdateService` | Disable upstream binary updates for this personal fork | No | No |

`AppCoordinator` is the only object that joins these parts. Views call coordinator methods. They
do not scan the menu bar or post input themselves.

## Visibility has two states

`StatusBarEngine.State` has two values.

| State | Always hidden section |
|---|---|
| `resting` | Closed |
| `open` | Open |

The engine uses one large status item length as the Always hidden boundary. Everything right of it
stays inline until macOS overflows it. The control item stays to the right. macOS keeps each status
item's preferred position through its autosave name. The section opens only during a confirmed move
sequence or a debug launch flag and returns to rest shortly after; no timer, event, or trigger opens
it.

All clicks, hotkeys, picker actions, and menu commands call the coordinator. A normal control-item
click opens the shelf; Option-click opens the picker. The shelf, the picker, and overflow access
share one authentication path.

## A safe item move has one fixed flow

1. The user selects a new section for one item.
2. The coordinator opens the Always hidden section.
3. The scanner reads the live menu bar.
4. The coordinator matches the selected item to the fresh result.
5. The status bar engine gives the target point for the requested section.
6. `ItemMoveService` validates the source frame, target point, and screen.
7. The service posts one Command-drag and returns the pointer to its old position.
8. The scanner reads the live menu bar again.
9. The store saves the rule only when the boundary frames confirm the new section.
10. The coordinator restores the resting state.

There can be only one move at a time. A failed validation or failed confirmation leaves the saved
rule unchanged.

## Geometry is temporary evidence

A menu bar item frame is valid only for the scan that returned it. Saved state contains no screen
coordinates and no Accessibility objects.

The move service rejects empty or very large source frames. Both endpoints must be on a current
screen. macOS owns menu bar overflow around a camera notch, so BarShelf does not reject a move just
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
click on BarShelf explicitly ends the session and restores the hidden layout.

## Local state uses one versioned document

`StateStore` writes this file with an atomic replace.

```text
~/Library/Application Support/BarShelf/state.json
```

`BarShelfDocument` contains its format version, settings, item rules, group names, and profiles.
JSON dates use ISO 8601. Import rejects a document with an unknown version.

Menu bar frames and Accessibility elements stay in memory. They are never written to disk.

## Permissions and system changes are narrow

- Accessibility is required to list, open, and move other apps' status items.
- Touch ID or the Mac password is used only when reveal protection is on.
- Launch at Login is optional and uses the main app service.
- Tighter spacing changes two user-level macOS preferences. BarShelf records the old values and
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

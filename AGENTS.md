# Agent notes

Barkeep is a local native macOS menu bar manager. It uses Swift 6, an AppKit lifecycle and status
bar, SwiftUI views, and XcodeGen. The personal fork deliberately removed Sparkle so an upstream
binary update cannot overwrite custom behavior.

## Product rules

- Every item belongs to **Always visible**, **Hidden**, or **Always hidden**.
- Click opens the overflow-first item picker. Option-click reveals all items in the physical bar.
  Right-click opens the management menu.
- `Command-Backslash` toggles items in the physical bar. `Command-Shift-Space` opens the picker.
- Only a direct item-section/reorder action or selected-item temporary access can post a
  Command-drag. An explicit end of temporary access (dots, Escape, Quit) can return that item.
- A move must use fresh Accessibility data and must pass a second scan before state is saved.
- Launch, wake, display events, app events, timers, and updates must never move an item.
- Touch ID or Mac password protection applies to all reveal paths, including search and triggers.
- Barkeep uses no account, telemetry, cloud sync, or Screen Recording.
- Saved settings, rules, and profiles stay under Application Support.
- Update failure cannot block app launch or the menu bar engine.

Read `docs/PRODUCT.md` before you change visible behavior. Keep `README.md` and
`docs/TROUBLESHOOTING.md` accurate when a user-facing feature changes.

## Repo map

```text
Sources/Barkeep/App/             app lifecycle and coordination
Sources/Barkeep/Models/          settings, rules, profiles, and runtime types
Sources/Barkeep/StatusBar/       visibility boundaries and menu bar icons
Sources/Barkeep/Accessibility/   scans, permission checks, and confirmed moves
Sources/Barkeep/Permissions/     guided Accessibility setup
Sources/Barkeep/Storage/         local versioned JSON state
Sources/Barkeep/System/          hotkeys, triggers, login, spacing, and update policy
Sources/Barkeep/UI/              settings and item-picker windows
Tests/BarkeepTests/              unit tests
scripts/                         build, install, DMG, and release entry points
.github/workflows/               public CI and release validation
```

## Commands

```sh
make check
make build
make local-build
make install
make dmg
```

`make check` runs XcodeGen before `xcodebuild test`. Generated `Barkeep.xcodeproj`, `.xcode-build`,
and `dist` files are ignored. Do not commit them.

## App structure

`AppCoordinator` is the integration point. It owns the status bar engine, scanner, mover, triggers,
hotkeys, windows, and state store. Views call coordinator methods and observe coordinator or store
state. Do not let views post input or make raw Accessibility calls.

Most app code is isolated to `@MainActor`. `AccessibilityScanner` and `ItemMoveService` each use one
private serial queue for blocking Accessibility or Core Graphics work. Keep shared mutable state on
its existing actor or queue.

`StatusBarEngine` owns exactly three status items.

1. The Barkeep control item
2. The Hidden boundary
3. The Always hidden boundary

All reveal actions must go through `AppCoordinator.requestReveal(all:)`. This keeps authentication
and auto-hide behavior consistent.

## Accessibility and move safety

Treat item frames as temporary evidence. Never save geometry or `AXUIElement` objects to disk.

For Settings section/order moves, keep the item move sequence in this order.

1. Open all sections.
2. Scan the live menu bar.
3. Match the selected item.
4. Read current boundary frames.
5. Validate both endpoints and their current screens.
6. Post one Command-drag.
7. Return the pointer to its earlier position.
8. Scan again.
9. Save only after the new section is confirmed.
10. Restore the earlier reveal state.

There can be only one active move. A failure must keep the earlier saved rule and show a useful
message. Do not add background repair or pointer movement.

macOS owns menu bar overflow around a camera notch. Settings moves must not be rejected only because
their cursor path crosses the center of a notched display; the second scan decides whether they land.

The permission helper opens the exact Accessibility page, follows the System Settings window, and
offers the signed app as a file drag source. Keep its pasteboard payload narrow. Do not add a broad
permission to work around one move failure.

## State and settings

`StateStore` writes one versioned JSON document with an atomic replace.

```text
~/Library/Application Support/Barkeep/state.json
```

Import must reject unknown document versions. New saved fields need safe defaults so old documents
continue to decode. Add a migration before you change the meaning of existing fields.

Spacing changes write the `NSStatusItemSpacing` and `NSStatusItemSelectionPadding` preferences.
Always preserve the old values and restore them when the feature is turned off.

Profiles and imports currently load stored rules and settings only. They do not move every live item.
Do not describe them as automatic layout restoration or add automatic moves without a new product
decision and a confirmed, user-controlled flow.

## Trigger lifecycle

`TriggerCenter.update(settings:)` stops existing timers, monitors, and observers before it creates
the required set. Any new optional trigger must follow the same ownership rule.

Idle work must stay near zero. Do not add a continuous Accessibility scan. Search can use its
current snapshot and request one refresh.

## Current feature boundary

The data model contains fields for planned work. The current UI does not provide a second menu bar,
custom menu bar styling, low-battery reveal, group editing, network triggers, script triggers,
automation, or editable hotkeys. Do not claim these features in public docs until the working UI and
tests exist.

## Testing

Add unit tests for pure state and geometry changes. Run `make check` for every source or project
change. A docs-only change can use focused link, style, and diff checks.

CI must continue to complete these checks.

- Generate the Xcode project
- Run unit tests with code signing off
- Build the complete app bundle
- Check that no upstream automatic-update feed is present
- Verify the app signature
- Launch the app and confirm that it stays running

Synthetic item moves need a signed local app and macOS Accessibility access. Test them with the same
archive that will ship. A source-text test does not prove that a real move worked.

## Release shape

- macOS 14 or later
- One app target and one unit test target
- Developer ID signing and hardened runtime
- Apple notarization and DMG stapling
- SHA-256 checksum with every public DMG

The main app needs a Developer ID signature and secure timestamp for a public release and must not
contain `com.apple.security.get-task-allow`.

Never commit signing identities, notary credentials, private keys, `release.env`, or release
artifacts.

The inherited `scripts/release.sh`, `appcast.xml`, and upstream publish workflow are not the release
path for this fork unless they are deliberately redesigned for a separate repository and identity.

GitHub issues are open. Pull request creation is limited to repository collaborators.

## HS custom-fork context and product goal

This checkout is intended to become a personal, simpler replacement for Bartender on HS's Mac.
Do not assume the upstream product behavior is the desired behavior merely because it already
exists. Preserve the upstream safety constraints above, but optimize the user-facing workflow for
the concrete overflow problem described here.

### Why this project exists

On 2026-08-31, Bartender stopped being usable after HS upgraded to macOS 26.5.1 Tahoe. The installed
copy was Bartender 5.2.3. Clicking its three-dots menu-bar control made the control disappear because
Bartender was actually crashing. Three crash reports were found that day under
`~/Library/Logs/DiagnosticReports/`, including one produced at the exact time of the test. Bartender's
own release notes say Bartender 5 is incompatible with Tahoe and requires the paid Bartender 6
upgrade. Rather than pay for another major version, HS chose to investigate an open-source base for
a personal replacement.

Upstream Barkeep 0.1.1 was selected from:

```text
https://github.com/iannuttall/barkeep
```

The upstream repository was cloned into this directory on 2026-08-31. HS also installed the signed
upstream release at `/Applications/Barkeep.app`. Treat `origin/main` as upstream source unless the
remote configuration later says otherwise. Ask before committing any changes.

### The actual user problem

HS has more right-side menu-bar icons than fit on a notched MacBook display. macOS pushes some
running menu-bar-only applications leftward behind the black camera/notch region or beyond the
available right-side strip. Their icons then become unreachable, even though the applications are
still running and may have no Dock window or other practical way to open their controls.

The primary goal is not merely to expand and collapse hidden icons in the same already-crowded menu
bar. That is Barkeep's current normal-click behavior and does not reliably solve notch overflow.
The desired interaction is:

1. HS chooses which important icons remain physically visible in the macOS menu bar.
2. All remaining detected menu-bar items are available from a reliable software picker that is not
   constrained by physical menu-bar width or the camera notch.
3. A normal click on a small Barkeep control, preferably `...` or a similar compact symbol, opens
   that picker immediately.
4. The picker shows recognizable app icons and names, supports quick search, and distinguishes
   visible items from hidden/overflow items without making the interface complicated.
5. Clicking an item in the picker opens that item's real menu or otherwise activates the same
   control the user would have clicked in the macOS menu bar.
6. Arrangement and preferences remain available, but they are secondary management actions rather
   than the primary click behavior.

The intended mental model is an **overflow menu for every running menu-bar app**, not a temporary
attempt to squeeze all hidden icons back into the physical menu bar.

### Findings from the initial live inspection

The upstream right-click menu currently provides Show/Hide Hidden Items, Show All Items, Find
Item, Arrange Items, Check for Updates, and Quit. `Arrange Items` displays three columns: Always
visible, Hidden, and Always hidden. `Find Item` already contains much of the needed mechanism: it
scans detected menu-bar items, shows app icons and names, filters by text, and calls
`AppCoordinator.activate(_:)`, which uses an Accessibility `AXPress` action on the selected menu-bar
element.

The installed app did not yet have macOS Accessibility permission during the initial inspection.
Consequently, Arrange Items showed zero items in all three columns, Find Item could not populate,
and no real inventory or behind-the-notch activation test was completed. Enabling Barkeep under
System Settings > Privacy & Security > Accessibility is therefore the next required live-test step.
Because this is a macOS security-setting change, obtain the user's confirmation immediately before
changing it through UI automation.

The installed app was restarted with `--show-settings` during inspection and was left running with
its Settings window available. Its bundle identifier is `is.ian.barkeep` and its installed version
was 0.1.1.

### Recommended first customization

Start with the smallest behavior change that tests the product idea:

- Change a normal control-item click from `handlePrimaryClick`'s reveal/hide toggle to opening an
  overflow picker derived from the existing search panel.
- Keep Option-click or explicit right-click commands available for the old reveal-all behavior if
  it remains useful.
- Rename and simplify `Find Item` into the main overflow experience; avoid creating two overlapping
  picker implementations.
- Add a compact route from the picker to Arrange Items.
- Preserve on-demand scanning and avoid a continuous Accessibility poll.
- Verify that off-screen or notch-displaced `AXExtrasMenuBar` children remain discoverable and that
  `AXUIElementPerformAction(..., kAXPressAction)` opens them without first forcing them into visible
  geometry. This is the central technical hypothesis and must be tested on HS's actual crowded menu
  bar before declaring the solution complete.
- If AXPress fails for truly off-screen items, investigate a safe activation fallback that does not
  depend on dragging every item into the physical bar and does not move the pointer in the
  background. Document macOS limitations honestly rather than reporting unreachable items as
  available.

The first picker should favor clarity over feature breadth. Do not begin with a second decorative
menu bar, styling system, scripting engine, network triggers, or automatic layout repair. Those do
not address HS's immediate access problem.

The initial source implementation of this customization was added after this handoff was written:
normal click now opens an overflow-first picker, the picker separates Hidden & Overflow from
Visible items, it provides search, refresh, and an Arrange Visible Items route, and the default
control icon is an ellipsis. Live activation remains unverified until Accessibility is granted and
a custom build can be installed.

The fork also removed the upstream Sparkle package and feed. `UpdateService` is intentionally a
disabled compatibility shim so existing conditional UI compiles while showing no update controls.
Never restore the upstream feed: it could replace the custom app with the upstream binary.

### Local development state

At the time of the initial investigation, this Mac had Swift 6.3.2 and Apple Command Line Tools,
but not a usable full Xcode installation selected for `xcodebuild`. `xcodegen` was also absent, and
`security find-identity -p codesigning` reported no valid code-signing identities. Thus `make check`
could not run because `xcodegen` was missing. A local ad-hoc build is supported by the upstream
scripts, but its changing signature may cause macOS to forget Accessibility permission after
rebuilds. Plan installation, Xcode/XcodeGen setup, bundle identity, update-feed removal or
replacement, and signing deliberately before replacing the signed upstream app with a custom
build.

`make local-build` is a supported fallback for this specific machine. It uses `swiftc` to build the
no-Sparkle source into `dist/Barkeep HS.app` with bundle identifier `com.hsurden.barkeep` and an
ad-hoc signature. It deliberately does not overwrite `/Applications/Barkeep.app`. Expect macOS to
forget Accessibility permission after some rebuilds until a stable signing identity is available.

### Single-item overflow access (2026-09-06)

HS approved bringing only the selected overflow icon to the left edge of the currently visible
icons (for example, left of Wi-Fi), leaving it for HS to click, and returning it when the dots
are clicked again. Overflow selection must not send AXPress or open the native menu automatically. Keep the original neighbor identities only in memory, confirm both moves, and
leave saved rules unchanged. The user rejected the visible grab/drag and full-group reveal.
Temporary access uses fresh AX-to-WindowServer matching, the original app PID even when Control
Center hosts the window, and scoped directed events. Keep the hidden section closed. Confirm the
whole selected icon clears the notch and precedes the leftmost visible neighbor before the temporary session starts.
No timers or background events may initiate a return move. Direct routing relies on undocumented
window fields; only signed, live round trips validate compatibility. See docs/SINGLE-ITEM-ACCESS.md.

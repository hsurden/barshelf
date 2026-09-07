# BarShelf product rules

This document defines the behavior that users can depend on. Keep these rules stable unless a
product decision changes them.

## Every menu bar item belongs to one section

BarShelf always uses the same two names and meanings.

1. **In the menu bar** items stay inline until macOS overflows them behind the notch.
2. **Always hidden** items stay in the shelf and picker without consuming physical menu-bar space.

The Items screen shows both sections at the same time, grouped by where each icon really is, not
by its saved rule. Selecting an item and pressing the arrow between the columns, or dragging it
across, moves it immediately through the confirmed move path. The in-bar column reorders the real
bar by drag. A rule that says Always hidden while macOS keeps drawing the icon is dropped after two
consecutive scans, so the columns and the shelf never disagree with the bar. There is no separate
reveal-toggle section and no classic hide-and-reveal mode.

## Main controls stay predictable

- A click opens a stable shelf snapshot.
- The overflow gear opens a menu below it: **Settings**, then **Quit BarShelf**.
- An Option-click opens the searchable item picker.
- A right-click opens a short command menu.
- `Command-Backslash` opens or closes the shelf.
- `Command-Shift-Space` opens the item picker.

The shelf includes both deliberately hidden items and items currently displaced by physical
overflow. Its contents do not reshuffle until it is closed and reopened. Selecting an overflow item
requests one temporary move of its real status control to the left edge of the visible icons, before
the leftmost currently drawable icon. The hidden group stays closed throughout the move. Selecting
an overflow entry exposes the icon only; it does not send AXPress or open its menu. The user clicks
the real icon when ready. The icon must be confirmed at that left edge and fully outside the notch
before the temporary session begins. It remains available after its menu closes; Escape or a normal
BarShelf click requests a verified return to its original neighbors. There is no automatic timeout.
Temporary moves never change saved rules or priority order. Window-addressed input avoids a visible
pointer drag and also handles the return. If a return fails, BarShelf retains its return address in
memory and offers another explicit click to retry. The picker supports filtering and links directly
to arrangement. The right-click menu contains the shelf, the picker, and Settings. Less common
settings stay in the settings window. The App section in Settings includes an explicit Quit BarShelf
HS action.

## Item moves require a direct user action

BarShelf can post a Command-drag after the user chooses a new section for one item, explicitly
reorders it, or selects an overflow item for temporary access. Closing that temporary session
authorizes the return move; quitting BarShelf first attempts this return. The app
must make a fresh Accessibility scan before the move and another scan after it. It saves the new
rule only when the second scan confirms the result.

Launch, wake, display changes, app changes, timers, and update checks must never move an item.
BarShelf can explain a problem and offer a user action. It cannot repair the layout in the
background.

## Accessibility setup stays short

BarShelf does not use a long onboarding flow. When Accessibility access is missing it uses this
short process.

1. Register the macOS permission request.
2. Open the Accessibility page in System Settings.
3. Show a small guide over System Settings.
4. Provide a draggable BarShelf app tile when the app is missing from the list.
5. Close the guide after macOS grants access.

The app must explain why it needs the permission. It must not ask for Screen Recording to provide
the core menu bar features.

## Settings start with quiet defaults

These defaults keep idle work and surprise behavior low. There are no hover, scroll, click,
app-change, battery, or display triggers: nothing opens the Always hidden section except a
confirmed move sequence, and it closes again on its own shortly after.

| Setting | Default |
|---|---|
| Click the BarShelf icon | Open the overflow shelf |
| Require Touch ID or the Mac password | Off |
| Start at login | Off |
| Show a Dock icon | Off |
| Use tighter item spacing | Off |

## Icons stay small and native

Ellipsis is the default. BarShelf also provides seven monochrome menu bar symbols.

- Dot
- Ring
- Ellipsis
- Diamond
- Chevrons
- Line
- Sparkle
- Grid

The expanded state can change the symbol, but every symbol must remain a template image that works
with light and dark menu bars.

## Private data stays local

BarShelf has no account, telemetry, or cloud sync. It stores settings, item rules, and profiles in
one versioned JSON document under Application Support. Export uses the same document format.

Persistent item identity must not depend on mutable status text. BarShelf uses an Accessibility
identifier when the owner provides one and otherwise reconciles a stable per-owner slot. Older
label-based rules migrate only after a live scan provides matching evidence.

Touch ID uses `LocalAuthentication`. Launch at Login uses `SMAppService`. The personal fork does not
load an upstream binary update feed; upstream changes are reviewed as source before merging.

## Current limits must stay visible

The current app does not include a second menu bar, custom menu bar styling, low-battery reveal,
network triggers, script triggers, automation, user-defined hotkeys, or a group editor.

Profiles save stored rules and settings. Loading a profile does not yet move every real item into
place. Import also loads stored rules and settings without rearranging the live menu bar. Do not
describe either action as automatic layout restoration until the app confirms each real move.

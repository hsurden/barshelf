# Barkeep product rules

This document defines the behavior that users can depend on. Keep these rules stable unless a
product decision changes them.

## Every menu bar item belongs to one section

Barkeep always uses the same three names and meanings.

1. **Always visible** items stay visible.
2. **Hidden** items stay in the picker and can also appear through an explicit physical reveal.
3. **Always hidden** items stay in the picker without consuming physical menu-bar space.

The Items screen shows all three sections at the same time. A user can drag an item or use its
section menu. Drag and drop is a fast option, but it is not the only way to arrange items.

## Main controls stay predictable

- A click on the Barkeep icon opens the item picker.
- An Option-click toggles all hidden items.
- A right-click opens a short command menu.
- `Command-Backslash` toggles the Hidden section.
- `Command-Shift-Space` opens the item picker.

The picker lists Hidden & Overflow items before Visible items, supports filtering, opens a selected
item's real menu, and links directly to arrangement. The right-click menu contains management and
physical-reveal actions. Less common settings stay in the settings window.

## Item moves require a direct user action

Barkeep can post a Command-drag only after the user chooses a new section for one item. The app
must make a fresh Accessibility scan before the move and another scan after it. It saves the new
rule only when the second scan confirms the result.

Launch, wake, display changes, app changes, timers, and update checks must never move an item.
Barkeep can explain a problem and offer a user action. It cannot repair the layout in the
background.

## Accessibility setup stays short

Barkeep does not use a long onboarding flow. When Accessibility access is missing it uses this
short process.

1. Register the macOS permission request.
2. Open the Accessibility page in System Settings.
3. Show a small guide over System Settings.
4. Provide a draggable Barkeep app tile when the app is missing from the list.
5. Close the guide after macOS grants access.

The app must explain why it needs the permission. It must not ask for Screen Recording to provide
the core menu bar features.

## Reveal settings start with quiet defaults

These defaults keep idle work and surprise behavior low.

| Setting | Default |
|---|---|
| Click the Barkeep icon | Open item picker |
| Hide items again | On, after 5 seconds |
| Hide when the active app changes | Off |
| Reveal on hover | Off |
| Reveal on scroll | Off |
| Reveal from any menu bar click | On |
| Keep items open on an external display | Off |
| Require Touch ID or the Mac password | Off |
| Start at login | Off |
| Show a Dock icon | Off |
| Use tighter item spacing | Off |

Optional triggers must have clear owners. Their timers, event monitors, and observers must stop
when the user turns the related setting off.

## Icons stay small and native

Ellipsis is the default. Barkeep also provides seven monochrome menu bar symbols.

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

Barkeep has no account, telemetry, or cloud sync. It stores settings, item rules, and profiles in
one versioned JSON document under Application Support. Export uses the same document format.

Touch ID uses `LocalAuthentication`. Launch at Login uses `SMAppService`. The personal fork does not
load an upstream binary update feed; upstream changes are reviewed as source before merging.

## Current limits must stay visible

The current app does not include a second menu bar, custom menu bar styling, low-battery reveal,
network triggers, script triggers, automation, user-defined hotkeys, or a group editor.

Profiles save stored rules and settings. Loading a profile does not yet move every real item into
place. Import also loads stored rules and settings without rearranging the live menu bar. Do not
describe either action as automatic layout restoration until the app confirms each real move.

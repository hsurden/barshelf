# Remove classic hide-and-reveal mode

Date: 2026-09-06

## Goal

The overflow shelf is the only menu bar behavior. The Menu bar mode picker and every piece of
classic hide-and-reveal machinery are removed rather than left dormant.

## Model

- Delete `MenuBarMode` and the optional `menuBarMode` settings field.
- `VisibilityZone` has two cases: `alwaysVisible` and `alwaysHidden`.
- Remove settings: `autoRehide`, `rehideDelay`, `hideOnAppChange`, `showOnHover`, `hoverDelay`,
  `showOnScroll`, `showOnMenuBarClick`, `showOnLowBattery`, `lowBatteryLevel`,
  `alwaysShowOnExternalDisplay`.
- Keep `requireAuthentication`; the shelf, picker, and single-item access honor it.

## State migration

- Unknown settings keys are ignored by the decoder; no code needed.
- A saved rule whose zone decodes as the old `hidden` value maps to `alwaysVisible`. This applies
  to the top-level rules and to every profile's rules. Import uses the same decoder.
- A unit test loads the old fixture with a `hidden` rule and a `classic` mode value and checks
  the result.

## Status bar engine

- Two status items: the control and the Always hidden boundary. The hidden boundary item, its
  autosave name, and `setMode` are removed.
- State enum: `resting` (Always hidden section closed, everything else inline) and `open`
  (section opened for a confirmed move or the debug move flag). No divider glyph is drawn.

## Coordinator

- Keep only the shelf side of every former mode branch.
- Delete `requestReveal`, `reveal`, `hide`, the classic rehide path, the classic scan path,
  `revealHiddenItemsForLaunchTest`, the classic click and Option-click paths, and the classic
  right-click items.
- Remove the `--show-hidden-items` launch flag.
- Delete `TriggerCenter`.
- The shelf's short tuck-back after a temporary session is unchanged.

## Settings UI

- Behavior tab: remove Menu bar mode, Show and hide, and Ways to reveal. Keep Privacy, App, and
  Keyboard shortcuts. Command-Backslash is labeled "Open or close the shelf".
- Items tab: always the two shelf columns with shelf titles; `ZonePresentation` becomes
  constants.

## Docs

Update `docs/PRODUCT.md`, `README.md`, `docs/TROUBLESHOOTING.md`, and `CLAUDE.md`: two
sections, two status items, no reveal triggers, no `requestReveal` rule, and a defaults table
limited to settings that exist.

## Tests

Remove or rewrite tests that reference the old zone, three-frame boundary ordering, and classic
defaults. Add the migration test and a two-boundary geometry test. `make check` must pass.

## Out of scope

No change to the shelf, single-item access, priority ordering, or spacing. No new features.

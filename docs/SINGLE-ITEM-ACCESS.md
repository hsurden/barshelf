# Single-item access in BarShelf

Original HS interaction (2026-09-06): choose one overflow app, put its real icon at the left edge of the
visible controls (currently left of Wi-Fi), let HS click it to open the native interface, then click
the dots to put it back. Overflow selection does not automatically press the selected icon. The
hidden group stays closed, without a visible pointer drag. Saved rules do not change. The return
address contains neighbor identities in memory, never persisted coordinates.

As of 2026-09-10, access falls back to a drawable slot beside BarShelf's control when the original
left-edge slot is blocked. Confirmation follows the chosen anchor identity, while return still
uses the original neighbors. Settings exposes Return Icon as another explicit return action.

## Evidence from other managers

[Bartender's feature description](https://www.macbartender.com/) says that it temporarily hides
currently visible items to make room for items obscured by the notch. That is published behavior;
it does not establish how Bartender's private implementation moves an individual icon.

[Ice's source](https://github.com/jordanbaird/Ice/blob/0.11.13-
dev.2/Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift) contains temporary-item access with a
neighboring-item return destination. Its move implementation addresses events to an owning process
and window, with event delivery synchronization and live frame checks. This suggests that an icon
need not always be grabbed by an ordinary pointer hit. No Ice implementation code was incorporated
into BarShelf.

## Implementation and alternatives

1. Direct-to-window move: match a fresh Accessibility item to an unambiguous live status-item window
   associated with the AX owner, allowing the known Control Center host on Tahoe. Implemented in
   `MenuBarWindow.swift` and `WindowDirectedMove.swift`: route down to the original app PID with the
   window ID, wait for its live origin to change, and release through the session and app. Tahoe can
   consume the release before an event tap observes it; fresh AX layout verification decides success.
   Every tap is scoped to the requested operation. There are no background event listeners or scans.
2. Temporarily make room: hide a small group of visible controls while the chosen item is in use,
   then restore them on the dots click. Moving BarShelf's own divider may help, but by itself it cannot
   arbitrarily extract a single icon from a group. This changes the visible layout and should remain
   a fallback product choice, not a silent action on every click.
3. A slot that replaces the dots: temporarily use the dots' width for the selected real icon, with
   a small return button below it. This avoids reserving idle space, but changes HS's requested
   return interaction and still requires a reliable way to move the real source.

The first experiment best complements the requested interaction; a proxy image below the bar does
not itself move another app's native menu or popover.

## Verification

- `make check` is blocked by missing XcodeGen; full Xcode is also unavailable on this Mac.
- The full app compiles using `make local-build` with Command Line Tools.
- Placement and window-matching tests run through a local Swift assertion harness.
- The final signed build passed a live Rectangle round trip on 2026-09-06 at 14:27 on the built-in
  notched display: AX x=-4016 → x=1006 (left of Wi-Fi at x=1053), then verified original neighbors.
  Both directed down/release sequences completed without delivery timeouts; the event portion took
  about 90 ms outward and 65 ms returning, followed by fresh AX confirmation. The hidden group
  remained closed. These timings exclude scanning and are not a general performance guarantee.
- All 13 placement/window test methods passed through the local Swift harness. Full XCTest remains
  unavailable because `make check` stops at missing XcodeGen.
- Unit tests cover fresh neighbor positions, exited neighbors, section-boundary fallback, full
  notch clearance, ambiguous/hosted window matching, direction-dependent insertion coordinates,
  and choosing the leftmost visible neighbor instead of the dots.
- Menu/popover behavior is owned by each app. The move test does not by itself prove that every
  app opens its menu correctly. Multi-display movement has not been verified.

## Historical interaction decision (2026-09-06)

HS observed the menu opening shortly after BarShelf incorrectly reported that it had failed.
AXPress had collapsed every non-success response into false. Uncertain responses now remain
unconfirmed rather than being described as menu failures. Explicitly unavailable controls retain
recovery guidance. HS then chose the simpler overflow interaction: expose the icon only and let
him click it. That path no longer posts AXPress or waits for its reply. This leaves the verified
window move and return behavior intact. The local harness now includes three AX-result tests.

## Return geometry verification (2026-09-10)

A leftward return accounts for the selected native window's width, but caps that adjustment at
the destination window's width when inserting before a neighbor. Without the adjustment, Rectangle
landed before its original left neighbor. Without the cap, Weather's 66-point status window
overshot a 38–40-point neighbor and landed after it. The final Accessibility scan still requires
the original neighbor identities; a changed order is not accepted as a successful return.

The same signed build passed live shelf expose/return checks for Weather, Rectangle, and Chrome
on Jon's Mac. These checks verified placement and return, not opening every app's native menu.
The narrow-neighbor regression is covered by the unit suite. Failed returns offer explicit retry,
leave-in-place, and quit options; both leaving and quitting were verified live during debugging.

# Troubleshoot BarShelf

Use these checks before you reset settings or report a bug.

## Identify the app icon

BarShelf's app icon shows blue, turquoise, and orange tiles on a glass shelf. The menu bar control
uses the monochrome symbol selected in Settings, with three dots as the default.

## BarShelf cannot find menu bar items

Open **BarShelf Settings**, select **Advanced**, and check the Accessibility status. Select **Set
Up** if access is not allowed. Turn BarShelf on in **System Settings > Privacy & Security >
Accessibility**, then return to BarShelf and select **Refresh**.

Some apps do not expose their status item through macOS Accessibility. Include the app name in a
bug report when one item is missing but other items appear.

## macOS keeps asking for Accessibility access

Use the same installed app path and the same signing identity for each local build. `make install`
uses `~/Applications/BarShelf.app` and the local `BarShelf Signing` identity when available.
An ad hoc build can look like a different app after each rebuild.

Remove old BarShelf entries from the Accessibility list before you add the stable signed app again.
Do not move the app after macOS grants access.

## An item does not move to its new section

BarShelf rejects a move when the source frame, target point, or screen is not safe. Before the drag
starts, BarShelf waits until the item shows a stable position on the screen. macOS decides how menu
bar overflow fits around a camera notch. BarShelf saves the new section only when a second
Accessibility scan confirms that macOS completed the move.

macOS keeps some Apple items, for example Clock and Control Center, on the far right side. A
Command-drag cannot move these items, so BarShelf does not show them in the Items screen.

On a Mac with a camera notch, the menu bar can become full. macOS then parks the leftmost items
behind the notch and does not draw them. The Settings move path requires a drawable source and shows
a clear "menu bar is full" message when one is unavailable. Overflow access instead addresses the
icon's live window, but still needs enough drawable space for the selected icon. Close some menu bar
apps or turn on tighter item spacing, then try again.

Use these checks in order.

1. Select **Refresh** in the Items settings and make sure the item is listed.
2. Select the item and press the arrow between the lists instead of drag and drop.
3. Turn on tighter item spacing when the menu bar has no safe space.
4. Move the item by hand with Command-drag when macOS does not complete the move.

BarShelf keeps the old saved section after a failed move.

## Open settings or quit from the overflow shelf

Click the shelf's gear to open its menu. Choose **Settings** or **Quit BarShelf** below it.
Clicking the gear alone leaves settings closed.

## A shelf icon disappears while the shelf is open

Shelf membership is fixed for each opening. Close and reopen the shelf to take a new overflow
snapshot. If an item is missing immediately after opening, use the full picker and report the app
name; some apps do not expose a stable Accessibility item.

## An overflow icon does not come out or does not return

Overflow-shelf activation temporarily brings only the selected icon to the left edge of the visible
icons, such as just left of Wi-Fi. Click the exposed icon to open its native menu. Overflow
selection does not open it automatically, and the icon remains available after the menu closes.
There is no timeout. Press Escape or click BarShelf to return it to its original neighbors. The
hidden group stays closed; no visible pointer drag is performed. Saved sections and priority order
remain unchanged.

If the destination has no room, free menu-bar space or attach a roomier display and try again. If
window matching or delivery fails, refresh the shelf and retry; this routing is macOS-dependent. It
will not report a successful move at an unverified position. A failed return keeps its return
address for another explicit click on the three dots. If both original neighboring controls have
exited, BarShelf returns the icon beside the divider on its original side. Force-quitting BarShelf
during temporary access can leave the icon out; ordinary Quit attempts to return it first. The
signed Rectangle round trip was verified on the built-in notched display; other display
configurations may behave differently.

## A keyboard shortcut does nothing

BarShelf uses `Command-Backslash` to open or close the overflow shelf and
`Command-Shift-Space` to open the item picker.
Another app can register the same global shortcut first. Quit the other app or remove its shortcut,
then restart BarShelf.

The current version does not include a shortcut editor.

## Tighter spacing does not change the menu bar

Spacing changes take effect after you log out and log in. Turn the setting off before you remove
BarShelf. BarShelf then restores the preference values that it saved before the change.

## Loading a profile does not rearrange every item

Profiles currently load BarShelf's saved rules and settings. They do not post a set of automatic
item moves. Open the Items screen and move any real menu bar items that do not match the profile.

## Check for Updates is missing

This personal fork intentionally has no automatic upstream update command. Pull and review upstream
source changes instead; do not add the upstream binary feed to the custom app.

## Reset local state without deleting it

Quit BarShelf. Move its state file to a backup name.

```sh
mv "$HOME/Library/Application Support/BarShelf/state.json" \
   "$HOME/Library/Application Support/BarShelf/state.backup.json"
```

Open BarShelf again. It creates default state. Move the backup file back only while BarShelf is not
running.

## Send a useful bug report

Open a [GitHub issue](https://github.com/iannuttall/barkeep/issues). Include the following details.

- macOS version and Mac model
- Number and layout of connected displays
- App name for the affected menu bar item
- BarShelf action and the message that appeared
- Whether the move crosses a MacBook camera notch
- Whether the app came from GitHub or a local build

Do not attach `state.json` until you inspect it. It can contain app names and custom profile names.

## A menu opens after a short delay

Overflow selection only exposes the real icon; click it yourself to open its menu. BarShelf sends no
automatic click in this path, so it does not wait for or report a menu-opening acknowledgment.

For picker actions that directly activate an already-visible control, Accessibility may time out
while an app is opening or tracking its native menu. BarShelf treats this as an unconfirmed
acknowledgment, leaves the selected icon available, and does not show a failure alert or click again
automatically. A second click could close a menu that just opened. If nothing opens, click the real
icon yourself; the three dots still return it to overflow. An explicitly unsupported or unavailable
Accessibility control can still produce a recovery message.

# Troubleshoot BarShelf

Use these checks before you reset settings or report a bug.

## Identify the app icon

BarShelf's app icon shows blue, turquoise, and orange tiles on a glass shelf. The menu bar control
uses the monochrome symbol selected in Settings, with three dots as the default.

## Open Settings when the menu bar control is unreachable

If BarShelf is already running, open the same installed app again in Finder or Spotlight.
It shows **BarShelf Settings** using the running instance. Launch at login does not open Settings.

This gives accessibility-based tools a normal window to inspect. Compatibility with a particular
computer-use tool still needs a live check; reopening does not fix macOS's parked menu bar items.
Do not start a second copy of the executable to obtain a window.

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

On macOS Tahoe, first check **System Settings > Menu Bar > Allow in the Menu Bar** for the
affected app. An app switched off there may still appear in BarShelf's Accessibility inventory,
but macOS prevents its icon from appearing. BarShelf's **Always hidden** section is separate from
this system setting. Allow the app in macOS before arranging it in BarShelf.

In a live Chrome test, switching this setting on removed the "This item did not appear on the
screen" failure, but the move then reported "The current menu bar layout is not safe for this
move." Enabling the system setting is a prerequisite, not a guarantee that a crowded-bar move
will succeed.

BarShelf rejects a move when the source frame, target point, or screen is not safe. Before the drag
starts, BarShelf waits until the item and the open section boundary show stable positions. It keeps
the same boundary item when opening the section and rejects a stale, closed spacer frame. macOS decides how menu
bar overflow fits around a camera notch. BarShelf saves the new section only when a second
Accessibility scan confirms that macOS completed the move.
For **In the menu bar**, confirmation also requires the whole icon to be drawable outside the
notch. Being on the visible side of the divider alone does not count as a successful move.
When the source icon is behind the notch, a Settings move to **In the menu bar** uses its live
window to insert it beside BarShelf's control. This still requires a uniquely matched window,
a drawable destination, and a confirming scan; it never opens the selected app's menu.

macOS keeps some Apple items, for example Clock and Control Center, on the far right side. A
Command-drag cannot move these items, so BarShelf does not show them in the Items screen.

On a Mac with a camera notch, the menu bar can become full and icons can overflow behind the notch.
Do not confuse this with an app disabled under **Allow in the Menu Bar**. The Settings move path
requires a usable source position. Overflow access addresses the
icon's live window, but still needs enough drawable space for the selected icon. Close some menu bar
apps or turn on tighter item spacing, then try again.

Use these checks in order.

1. Select **Refresh** in the Items settings and make sure the item is listed.
2. Select the item and press the arrow between the lists instead of drag and drop.
3. Turn on tighter item spacing when the menu bar has no safe space.
4. Move the item by hand with Command-drag when macOS does not complete the move.

BarShelf keeps the old saved section after a failed move.

## Open settings or quit from the overflow shelf

If the menu-bar control is hard to reach, reopen BarShelf in Finder or Spotlight, then choose
**Open Shelf** in Items settings. This uses the same authentication check as the menu-bar control.

Click the shelf's gear to open its menu. Choose **Settings** or **Quit BarShelf** below it.
Clicking the gear alone leaves settings closed.

## A shelf icon disappears while the shelf is open

Shelf membership is fixed for each opening. Close and reopen the shelf to take a new overflow
snapshot. If an item is missing immediately after opening, use the full picker and report the app
name; some apps do not expose a stable Accessibility item.

## An overflow icon does not come out or does not return

Overflow-shelf activation temporarily brings only the selected icon to the left edge of the visible
icons, such as just left of Wi-Fi. If the notch blocks that slot, it uses the leftmost position
further right that clears the notch, and the icons to its left wait behind the notch until it
returns. After confirming the move, BarShelf leaves the icon for you to click; it does not open
the app's menu itself. The icon remains available after the menu closes.
There is no timeout. Press Escape, click BarShelf, or choose **Return Icon** in Settings to return it to its original neighbors. The
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

Overflow selection exposes the icon at a confirmed drawable position and lets you click its real
control. It does not automatically send an Accessibility press. A successful press response from
a directly activated visible picker item is not proof that its native menu opened.

For picker actions that directly activate an already-visible control, Accessibility may time out
while an app is opening or tracking its native menu. BarShelf treats this as an unconfirmed
acknowledgment, leaves the selected icon available, and does not show a failure alert or click again
automatically. A second click could close a menu that just opened. If nothing opens, click the real
icon yourself; the three dots still return it to overflow. An explicitly unsupported or unavailable
Accessibility control can still produce a recovery message.

## Returning an exposed icon fails

A failed return offers **Retry Return**, **Leave Icon Here**, and **Quit BarShelf**. Retry posts
one new return attempt. Leave Icon Here ends temporary access at the current position so other
actions work again. Quit BarShelf exits without another move. Neither choice reports a successful
return. The next normal inventory refresh reflects the actual layout.

Overflow selection exposes the real icon; click it yourself to open its controls. Close its native
menu before clicking BarShelf to return it. A failure to return is separate from the system's
Allow in the Menu Bar setting.

## An inactive app reports missing boundaries

An app disabled under macOS **Menu Bar → Allow in the Menu Bar** can remain in the shelf inventory
while its Accessibility icon is off the menu-bar row. BarShelf now checks for that unavailable icon
before building a temporary return address and explains how to enable it and refresh. This
geometry alone does not prove the switch is off, so the message also mentions the app's own icon
setting. No system setting is changed automatically.

If an icon returned to overflow but missed its original neighbors, the dialog now says that the
icon is back in overflow and offers **Keep Current Order**. This button performs no move; it accepts
the position already reached. BarShelf still does not claim that the original order was restored.

The shelf and searchable picker omit icons that macOS currently reports off the menu-bar row
or with invalid geometry. Real hidden icons and icons behind the notch remain available.
Unavailable items remain in Settings; enable them in macOS or their own app, then refresh
BarShelf (or reopen the shelf) to include them again. Availability is checked again at selection
time, so an item disabled after the shelf opened can still show recovery guidance.

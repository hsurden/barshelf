BarShelf 0.2.0

- Renamed from Barkeep HS to BarShelf (bundle identifier `com.hsurden.barshelf`)
- The overflow shelf is the only behavior; the classic hide-and-reveal mode, its Hidden section, and its reveal triggers are gone
- Every menu bar item is either In the menu bar or Always hidden
- The Items tab groups icons by where they really are, with arrows between the lists to hide or show the selected item
- Old settings and rules load unchanged; rules from the removed Hidden section become In the menu bar
- Release DMGs are signed with a personal certificate and are not notarized, so macOS asks for Open Anyway once

Custom fork — earlier unreleased changes

- Normal click opens an overflow-first menu-bar item picker instead of expanding the crowded bar
- The picker separates Hidden & Overflow items from Visible items
- The picker supports filtering, refreshing, and opening Arrange Visible Items
- Selecting an entry activates that item's real menu through Accessibility
- Ellipsis is the default control icon
- The upstream automatic-update feed is disabled so it cannot overwrite custom behavior

Upstream Barkeep 0.1.1 makes item moves more reliable and makes failure messages clear.

- Barkeep now waits until a hidden item is really on the screen before it starts a move
- A clear message appears when the menu bar is full and macOS parks the item behind the camera notch
- A clear message appears when an item never comes on the screen
- Clock and Control Center no longer appear in the Items screen, because macOS pins them and lets no app move them
- The hidden bar stays open while the pointer is in the menu bar area or while a menu is open, and it hides after you move away
- The troubleshooting guide explains the new messages and these macOS limits

Barkeep has no account, analytics, or Screen Recording access. It requires a Mac running macOS 14
or later.

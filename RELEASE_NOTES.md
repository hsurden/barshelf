Custom fork — unreleased

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

<div align="center">

<img src="Sources/Barkeep/AppIcon.icon/Assets/barkeep.svg" width="150" alt="Barkeep">

# Barkeep

**Keep a crowded macOS menu bar under control.**

Barkeep is a native menu bar manager for macOS. It keeps important items visible and puts
everything else one click away.

[Download for macOS](https://github.com/iannuttall/barkeep/releases/latest) ·
[Report a problem](https://github.com/iannuttall/barkeep/issues) · MIT licensed

</div>

---

## Put every item in one clear section

Barkeep splits the menu bar into two sections.

| Section | What Barkeep does |
|---|---|
| **In the menu bar** | These items stay inline until macOS overflows them behind the notch. |
| **Always hidden** | These stay in the shelf and picker without taking physical menu-bar space. |

Open the **Items** tab in Settings to see both sections together. Drag to reorder the bar, or use
the menu on an item's row to move it between sections. Barkeep checks the real menu bar after each
move. It saves the new section only when macOS completes the move.

The default Barkeep icon is a compact ellipsis. You can choose from eight monochrome symbols.

## Use Barkeep without leaving your current app

- Click the Barkeep icon to open a stable shelf of overflowed and Always hidden items.
- Click the shelf’s gear for **Settings**, followed by **Quit Barkeep HS**.
- Type while the shelf is open, or Option-click the icon, to open the searchable full picker.
- Right-click the icon for the shelf, the picker, and Settings.
- Press `Command-Backslash` to open or close the shelf.
- Press `Command-Shift-Space` to open the item picker.

Choose an overflow entry to temporarily put that app's real icon at the left edge of the visible
menu-bar icons (for example, just left of Wi-Fi). Click the exposed icon yourself to open its menu;
selecting it in overflow does not click it automatically. Only the selected hidden item comes out,
and the hidden group stays closed without a visible pointer drag. Click the three dots again or
press Escape to return it to its original neighbors. Closing the app's menu alone leaves the icon
available. Saved sections and priority order do not change.
If there is no room outside the notch or macOS refuses the move, Barkeep reports the failure and
attempts a verified return. This uses undocumented window routing and can vary across macOS releases.

There is no classic hide-and-reveal mode and no hover, scroll, or click trigger. Every item stays
in the bar until macOS overflows it, and the shelf is the one place to reach the rest.
The App section in Settings includes a Quit Barkeep HS button.

## Your menu bar data stays on your Mac

Barkeep has no account and sends no analytics. It does not use Screen Recording. It stores its
settings, item rules, and profiles in one local JSON file.

```text
~/Library/Application Support/Barkeep/state.json
```

Accessibility access lets Barkeep list, open, and move menu bar items. Barkeep makes a fresh
scan before a move and moves items only after an explicit arrangement or temporary-access action. Launch, wake,
display changes, and timers cannot move an item.

Touch ID or the Mac password can protect the shelf, the picker, and overflow access. Launch at
Login is optional and uses the macOS login item service.

## Install Barkeep

Download the latest DMG from the [GitHub releases page](https://github.com/iannuttall/barkeep/releases/latest),
drag Barkeep to Applications, and open it.

Barkeep supports macOS 14 or later. A local build also needs Xcode 16 or later and XcodeGen.

```sh
brew install xcodegen
make check
make install
```

This personal fork also has a Command-Line-Tools fallback for HS's current Mac, where full Xcode is
not installed:

```sh
make local-build   # Build dist/Barkeep HS.app without replacing the installed app
make install       # Install the signed build as ~/Applications/Barkeep HS.app
```

The fallback uses the local `Barkeep HS Signing` identity when it is available. `make install`
moves the previous installed copy to Trash, installs the newly signed build at the one canonical
path, and opens it. Without that identity, macOS can ask for Accessibility access again.

## Verify a downloaded build

Public builds use Developer ID signing and Apple notarization. After a release is available you
can check the installed app with these commands.

```sh
codesign --verify --deep --strict --verbose=2 /Applications/Barkeep.app
spctl --assess --type execute --verbose=4 /Applications/Barkeep.app
```

Each release also includes a SHA-256 checksum for its DMG.

```sh
shasum -a 256 ~/Downloads/Barkeep-*.dmg
```

## Build and test the app

```sh
make check       # Generate the Xcode project and run tests
make build       # Build and sign dist/Barkeep.app
make local-build # Build dist/Barkeep HS.app with Command Line Tools
make install     # Install to ~/Applications and open the app
make dmg         # Build a drag-install DMG
```

These are the main source areas.

```text
Sources/Barkeep/App/             app lifecycle and coordination
Sources/Barkeep/StatusBar/       status items and visibility boundaries
Sources/Barkeep/Accessibility/   item scanning and confirmed moves
Sources/Barkeep/System/          hotkeys, login, spacing, and update policy
Sources/Barkeep/UI/              settings, search, and permission views
Tests/BarkeepTests/              unit tests for state and core rules
scripts/                         build, install, DMG, and release commands
```

Read [AGENTS.md](AGENTS.md) before changing the app. The supporting docs cover the
[product rules](docs/PRODUCT.md), [architecture](docs/ARCHITECTURE.md),
[clean-room source audit](docs/AUDIT.md), [common problems](docs/TROUBLESHOOTING.md), and
[release process](docs/RELEASING.md).

## Current limits

The current app includes the two visibility sections, safe item moves, the overflow shelf, the
item picker, Touch ID protection, profiles, backups, and tighter item spacing. This personal fork
does not accept automatic upstream app updates; upstream changes are reviewed and merged as source.

A second menu bar, custom bar styling, low-battery rules, scripts, and network triggers are not
part of the current app. Profiles save Barkeep's stored rules and settings. Loading a profile does
not move every real menu bar item into place yet.

## Report bugs and request features

Open a [GitHub issue](https://github.com/iannuttall/barkeep/issues) with your macOS version, display
layout, the app that owns the menu bar item, and what Barkeep did. The
[troubleshooting guide](docs/TROUBLESHOOTING.md) lists safe checks for common problems.

Pull request creation is limited to repository collaborators. This keeps changes tied to the menu
bar safety rules and signed release checks.

## License

Barkeep uses the [MIT License](LICENSE).

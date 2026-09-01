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

Barkeep splits the menu bar into three sections.

| Section | What Barkeep does |
|---|---|
| **Always visible** | These items stay in the menu bar. |
| **Hidden** | These stay in the picker and can also be revealed in the physical bar. |
| **Always hidden** | These stay in the picker without taking physical menu-bar space. |

Open **Arrange Items** to see all three sections together. Drag an item to another section or
use the menu on its row. Barkeep checks the real menu bar after each move. It saves the new
section only when macOS completes the move.

The default Barkeep icon is a compact ellipsis. You can choose from eight monochrome symbols.

## Use Barkeep without leaving your current app

- Click the Barkeep icon to open a stable shelf of overflowed and Always hidden items.
- Type while the shelf is open, or Option-click the icon, to open the searchable full picker.
- Right-click the icon for arrangement, physical reveal controls, and other management actions.
- Press `Command-Backslash` to show or hide items.
- Press `Command-Shift-Space` to open the item picker.

Choose an entry to reveal its real status item and open that item's native menu. Barkeep restores
the resting layout only when you press Escape or click Barkeep again; revealed overflow items have
no automatic timeout. Use the arrangement button to decide
which important icons should remain physically visible. The picker remains usable when the menu bar
does not have enough width to display every managed item at once.

Barkeep can hide items again after a delay. It can also reveal them when you click, scroll, or
hover in the menu bar. Each optional trigger stops when you turn it off.
The App section in Settings includes a Quit Barkeep HS button.

## Your menu bar data stays on your Mac

Barkeep has no account and sends no analytics. It does not use Screen Recording. It stores its
settings, item rules, and profiles in one local JSON file.

```text
~/Library/Application Support/Barkeep/state.json
```

Accessibility access lets Barkeep list, open, and move menu bar items. Barkeep makes a fresh
scan before a move and posts a Command-drag only after you choose a new section. Launch, wake,
display changes, and timers cannot move an item.

Touch ID or the Mac password can protect every reveal path. Launch at Login is optional and uses
the macOS login item service.

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
Sources/Barkeep/System/          hotkeys, triggers, login, spacing, and update policy
Sources/Barkeep/UI/              settings, search, and permission views
Tests/BarkeepTests/              unit tests for state and core rules
scripts/                         build, install, DMG, and release commands
```

Read [AGENTS.md](AGENTS.md) before changing the app. The supporting docs cover the
[product rules](docs/PRODUCT.md), [architecture](docs/ARCHITECTURE.md),
[clean-room source audit](docs/AUDIT.md), [common problems](docs/TROUBLESHOOTING.md), and
[release process](docs/RELEASING.md).

## Current limits

The current app includes the three visibility sections, safe item moves, the item picker, reveal
triggers, Touch ID protection, profiles, backups, and tighter item spacing. This personal fork does
not accept automatic upstream app updates; upstream changes are reviewed and merged as source.

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

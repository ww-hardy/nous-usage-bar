# Nous Usage Bar — macOS menu bar widget

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

Live Nous Portal credit balance in your menu bar. Native Swift status item,
backend delegates to Hermes' own Nous account machinery (no credential
handling in the widget).

## Screenshot
![Nous Usage Bar menu bar widget](assets/screenshots/menu-bar.png)

## Docs
- **[ONBOARDING.md](ONBOARDING.md)** — first-run guide: how to connect your own Nous credentials (via Hermes' Nous Portal login), troubleshooting, and how the credential flow works.
- **[UPDATING.md](UPDATING.md)** — update strategy: pull from git + rebuild (`./update.sh`), why that's the right model, and alternatives.

## License
GPL-3.0 — see [LICENSE](LICENSE).

## What it shows
- Menu bar: `● $129.10` — total usable credits, colored dot (green > $30, orange > $10, red ≤ $10)
- Click: plan, subscription credits, top-up credits, monthly credits, renewal date
- Menu actions: **Open billing page…** (⌘B), **Top up…** (⌘T), **Refresh now** (⌘R), **Quit** (⌘Q)
- Refreshes every 5 min, plus every time the menu opens

## Files
```
nous-statusbar/
├── NousUsageBar.swift        # native Swift status item app
├── fetch_nous_usage.py       # backend: Hermes account fetch → JSON
├── Info.plist                # LSUIElement (no Dock icon) + AppIcon
├── assets/AppIcon.icns       # generated app icon
├── build.sh                  # reproducible: compile → bundle → sign → DMG+ZIP
└── dist/                     # distributable .dmg + .zip (from build.sh)
```

## Build a distributable
```bash
cd ~/Documents/Hermes/nous-statusbar
./build.sh
```
Produces `~/Applications/NousUsageBar.app` plus
`dist/NousUsageBar-<date>.dmg` and `.zip`.

## Update from git
```bash
./update.sh            # fetch latest release tag, rebuild, relaunch
./update.sh --force    # rebuild even if already on the latest tag
```
See [UPDATING.md](UPDATING.md) for the full strategy.

## In-app updates
The widget checks for updates **weekly** (and on launch) against the GitHub
latest-release API. Open the menu:
- **⬆ Update NousUsageBar — vX.Y.Z available** — runs the update (finds a local
  repo checkout and executes `update.sh`; falls back to the Releases page)
- **Check for Updates…** (⌘U) — manual check
- Status row shows installed vs latest version

**Re-generate the icon** (if you want a different one): replace
`assets/appicon-source.png` with any 1024×1024 PNG and re-run `./build.sh`
— it rebuilds the `.icns` automatically.

## Install on another Mac
- Download the latest **`NousUsageBar-<version>-signed.dmg`** from the
  [Releases page](https://github.com/ww-hardy/nous-usage-bar/releases),
  mount it, and drag `NousUsageBar.app` to `~/Applications`.
- **Requires** a working Hermes install (`~/.hermes/hermes-agent/venv/bin/python`)
  logged into Nous Portal (`hermes portal`). The widget shells out to Hermes'
  own account fetch — it never reads your OAuth token itself.
- The app is **Developer ID signed and notarized by Apple** — it opens with no
  Gatekeeper warning on macOS 12+. No right-click workaround needed.

## Signing & notarization
The release DMG is signed with a **Developer ID Application** certificate
(hardened runtime, `--timestamp`) and **notarized + stapled** by Apple, so
Gatekeeper accepts it on first open. To re-sign/notarize after a rebuild:
```bash
./sign.sh
```
This signs `~/Applications/NousUsageBar.app` with hardened runtime, builds a
fresh DMG, submits it to Apple's notary service (credential profile
`AC_PASSWORD`), and staples the ticket to both the app and the DMG. See
`signing/` for the certificates and keys — **never commit that folder**
(it's in `.gitignore`).

## Auto-start at login
```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.gieldanowski.noususagebar.plist
```
Or System Settings → General → Login Items → + → `NousUsageBar.app`.

## Quit / remove
- Quit: click the widget → **Quit NousUsageBar** (⌘Q)
- Uninstall: quit the app, then:
```bash
rm -rf ~/Applications/NousUsageBar.app
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.gieldanowski.noususagebar.plist 2>/dev/null
rm ~/Library/LaunchAgents/com.gieldanowski.noususagebar.plist
```

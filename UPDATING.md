# Updating NousUsageBar

This project is **source-distributed**: the repo contains the Swift source, the
fetch backend, and `build.sh` — the `.app` is built locally from that source.
So updates don't come as a re-downloaded binary; they come **from git**.

## TL;DR

```bash
cd <wherever-you-cloned-nous-usage-bar>
./update.sh
```

That fetches the latest release tag, rebuilds the app, swaps the running
instance, and relaunches it. Done.

**Or use the in-app button**: open the widget menu → **Update NousUsageBar**
(available when a newer release exists). The widget finds a local repo
checkout (standard locations) and runs `update.sh` for you — otherwise it
opens the GitHub Releases page. It also checks for updates automatically
every week and on launch.

### Bootstrap: your checkout is older than update.sh itself

`update.sh` was introduced after the first release. If your local checkout is
on a tag that predates it (e.g. `v1.0.0`), the script isn't in your working
tree yet. Bootstrap once onto the latest `main`, then use `update.sh` forever
after:

```bash
git fetch --tags --prune
git checkout main
git pull --quiet origin main
./update.sh
```

---

## Why git-pull is the right update strategy here

Two properties of this project make "pull from git + rebuild" the natural fit:

1. **The build is trivial and local.** `build.sh` is a single reproducible
   script — compile the one Swift file, bundle, adhoc-sign, package. There's
   no dependency tree to resolve, no server-side build step, no signing
   certificate needed. Rebuilding locally is cheaper than maintaining a
   hosted binary channel.

2. **GitHub is already the distribution point.** The repo (and its Releases)
   live on GitHub; pulling is one `git fetch`. Adding a second update channel
   (download server, Sparkle feed, Homebrew cask) would duplicate what git
   already gives us.

### Release vs `main`

- **Releases** (tags like `v1.0.0`) are the *stable* channel. `update.sh`
  tracks these by default — you get tested snapshots.
- **`main`** is the *development* line. It may contain unreleased work.
  Prefer releases for day-to-day updates; use `main` only if you want to
  follow bleeding-edge changes.

`update.sh` uses an **ancestry check**, not a string comparison: it only
updates when the latest tag is *not already contained* in your checkout. That
means running it repeatedly is a no-op, and it never "downgrades" a checkout
that's ahead of the newest tag.

---

## When to rebuild vs reinstall

| Situation | What to do |
|---|---|
| Normal update | `./update.sh` |
| A release note says "rebuild required" | `./update.sh --force` |
| You suspect a stale/corrupt build | `./update.sh --force` |
| Moving to a new Mac | Clone the repo, run `./update.sh --force` |
| You just want the latest DMG (no toolchain) | Grab it from the GitHub Releases page |

`--force` rebuilds even if you're already on the latest tag — useful after a
toolchain upgrade or a manual tweak to the source.

---

## The manual steps (what update.sh automates)

```bash
git fetch --tags                  # 1. get the latest release
git checkout v1.0.0               # 2. switch to it (or: git pull origin main)
./build.sh                        # 3. rebuild the .app
pkill -f NousUsageBar.app/Contents/MacOS   # 4. quit the running widget
open ~/Applications/NousUsageBar.app       # 5. relaunch the new build
```

That's the whole story. `update.sh` is just these steps, plus the up-to-date
check and the git-2.15 HTTP/1.1 quirk handled for you.

---

## Alternative strategies (and why they're not chosen here)

| Strategy | Verdict |
|---|---|
| **Sparkle auto-updater** | Overkill for a single-file GPL tool. Needs a signed appcast, a hosted feed, and Developer-ID signing — heavyweight for no real gain when `git pull` is one command. |
| **Homebrew cask** | Nice for end users, but requires maintaining a cask tap and a release ritual. Could be added later if the audience grows. |
| **Download new DMG each time** | Works, but loses the source/build in the repo — you'd still clone for updates. Redundant with git. |
| **GitHub Actions → auto-build DMG on tag** | A good *complement*: CI builds the distributable on every tag so non-developers can grab a ready DMG. Not yet set up — happy to add if you want it. |

---

## Future ideas

- A **`hermes`-powered update check** inside the widget itself (a menu item
  "Check for updates…" that runs the same ancestry logic).
- A **GitHub Actions workflow** that tags → builds → uploads the DMG to
  Releases automatically, so `update.sh` could offer "download the official
  DMG" as an alternative to rebuilding.

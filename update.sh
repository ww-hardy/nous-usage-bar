#!/bin/bash
# Update NousUsageBar by pulling the latest release from git and rebuilding.
#
# Strategy: the repo is the source of truth. Releases are tagged (v1.0.0, …);
# this script fetches tags, compares against the local checkout, and when a
# newer release exists it checks out that tag, rebuilds the app, swaps the
# running instance and relaunches.
#
# Usage:  ./update.sh            (from the repo root)
#         ./update.sh --force    (rebuild even if already on the latest tag)
#
# Bootstrap: if your checkout is on a tag that predates update.sh (e.g. it
# wasn't shipped in v1.0.0), first run:
#     git fetch --tags --prune && git checkout main && git pull origin main
# then use this script from then on.
#
# Dependencies: git, xcrun/swiftc (Xcode command line tools), and the repo
# cloned locally. No GitHub token needed — read-only fetch over HTTPS.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

# --- 0. GitHub needs HTTP/1.1 on git 2.15 (this machine) ----------------
git config http.version HTTP/1.1 2>/dev/null || true

# --- 1. Fetch the latest release tags ------------------------------------
echo "==> Fetching releases from origin…"
git fetch --tags --quiet --prune

LATEST_TAG=$(git tag --sort=-v:refname | grep -v '\^' | head -1 || true)
if [ -z "$LATEST_TAG" ]; then
  echo "    No release tags found — falling back to 'main'."
  LATEST_TAG="main"
fi

CURRENT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")

echo "    current : ${CURRENT_TAG}"
echo "    latest  : ${LATEST_TAG}"

# --- 2. Decide whether to update ------------------------------------------
# We are "up to date" if the latest release tag is an ancestor of HEAD — i.e.
# the local checkout already contains that release (or is ahead of it during
# development). String tag equality would wrongly "downgrade" a checkout that
# has commits beyond the newest tag.
if [ "$FORCE" -eq 0 ] && [ "$LATEST_TAG" != "main" ] \
   && git merge-base --is-ancestor "$LATEST_TAG" HEAD 2>/dev/null; then
  echo "✔ Already up to date (HEAD contains $LATEST_TAG) — nothing to do."
  exit 0
fi

# --- 3. Check out the target ---------------------------------------------
if [ "$LATEST_TAG" = "main" ]; then
  git checkout --quiet main
  git pull --quiet origin main
else
  git checkout --quiet "$LATEST_TAG" 2>/dev/null || git fetch --tags --quiet && git checkout --quiet "$LATEST_TAG"
fi
echo "==> On $LATEST_TAG"

# --- 4. Rebuild -----------------------------------------------------------
echo "==> Rebuilding…"
./build.sh

# --- 5. Swap the running app ----------------------------------------------
APP="$HOME/Applications/NousUsageBar.app"
echo "==> Relaunching app…"
pkill -f "NousUsageBar.app/Contents/MacOS" 2>/dev/null || true
sleep 1
open "$APP"

echo "✔ Updated to $LATEST_TAG — NousUsageBar relaunched."

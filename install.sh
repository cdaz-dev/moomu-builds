#!/usr/bin/env bash
# moomu, installed in one command (macOS):  curl -fsSL https://moomu.app/install | bash
#   1. downloads the newest moomu for macOS from moomu's public releases (github.com/cdaz-dev/moomu-builds)
#   2. puts moomu.app in /Applications (replacing an older one) and opens it
#   3. installs Claude Code with Anthropic's own installer if it isn't there yet (you sign in to it in moomu's
#      first run, in Claude Code's own window: moomu never sees your login)
#   4. installs a private copy of Node for moomu's browser if there's none (in ~/.moomu, nothing system-wide)
set -euo pipefail
BUILDS="cdaz-dev/moomu-builds"
say() { printf '\033[1m%s\033[0m\n' "$*"; }

case "$(uname -s)" in
  Darwin) ;;
  *) echo "This installer is for macOS. On Windows, run in PowerShell:  irm https://moomu.app/install.ps1 | iex"
     echo "Linux is coming soon."; exit 1 ;;
esac

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# the newest release with a Mac build in it (MOOMU_BASE: another place to download from)
if [ -n "${MOOMU_BASE:-}" ]; then
  url="$MOOMU_BASE/moomu-macos.zip"
else
  url="$(curl -fsSL "https://api.github.com/repos/$BUILDS/releases?per_page=30" \
        | grep -o '"browser_download_url": *"[^"]*/moomu-macos\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"$/\1/')"
fi
[ -n "$url" ] || { echo "Couldn't reach moomu's downloads. Check your connection and try again."; exit 1; }
build="$(printf '%s' "$url" | sed -n 's|.*/download/b\([0-9]*\)/.*|\1|p')"
say "downloading moomu${build:+ (build $build)}..."
curl -fL --progress-bar "$url" -o "$tmp/moomu-macos.zip"

say "installing to /Applications..."
pkill -x moomu 2>/dev/null || true
rm -rf "$tmp/app"; mkdir -p "$tmp/app"
ditto -x -k "$tmp/moomu-macos.zip" "$tmp/app"
rm -rf /Applications/moomu.app
ditto "$tmp/app/moomu.app" /Applications/moomu.app
xattr -dr com.apple.quarantine /Applications/moomu.app 2>/dev/null || true

if ! command -v claude >/dev/null && [ ! -x "$HOME/.local/bin/claude" ]; then
  say "installing Claude Code (Anthropic's own installer)..."
  curl -fsSL https://claude.ai/install.sh | bash
fi
# Claude Code's installer puts it in ~/.local/bin, which a Mac's Terminal doesn't search ("command not found"):
# that folder goes on the path for zsh and bash, once
if [ -x "$HOME/.local/bin/claude" ]; then
  for rc in "$HOME/.zshrc" "$HOME/.bash_profile"; do
    { [ "$rc" = "$HOME/.zshrc" ] || [ -f "$rc" ]; } || continue
    grep -qs '.local/bin' "$rc" || printf '\n# Claude Code (added by moomu'"'"'s installer)\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
  done
fi

# Node (moomu's browser runs on it): moomu's own copy if there's none, in ~/.moomu/node
if ! command -v npx >/dev/null && [ ! -x "$HOME/.moomu/node/bin/npx" ]; then
  say "installing Node for moomu's browser (its own copy)..."
  arch="$(uname -m)"; [ "$arch" = "x86_64" ] && arch="x64"
  file="$(curl -fsSL https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt | awk '{print $2}' | grep "darwin-$arch.tar.gz$" | head -1)"
  if [ -n "$file" ]; then
    mkdir -p "$HOME/.moomu"
    curl -fsSL "https://nodejs.org/dist/latest-v22.x/$file" | tar -xz -C "$tmp"
    rm -rf "$HOME/.moomu/node"; mv "$tmp/${file%.tar.gz}" "$HOME/.moomu/node"
  else echo "(couldn't find Node for this Mac: moomu will ask for it when its browser is first used)"; fi
fi

say "done. opening moomu ✦"
open /Applications/moomu.app

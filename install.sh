#!/usr/bin/env bash
# moomu, installed in one command (macOS and Linux):  curl -fsSL https://moomu.app/install | bash
#   1. downloads the newest moomu from moomu's public releases (github.com/cdaz-dev/moomu-builds)
#   2. macOS: puts moomu.app in /Applications (replacing an older one) and opens it. Linux: the AppImage in
#      ~/.local/share/moomu, moomu in your app menu and on your PATH (~/.local/bin/moomu), then opens it
#   3. installs Claude Code with Anthropic's own installer if it isn't there yet (you sign in to it in moomu's
#      first run, in Claude Code's own window: moomu never sees your login)
#   4. installs a private copy of Node for moomu's browser if there's none (in ~/.moomu, nothing system-wide)
#   5. downloads her voice (Chatterbox Turbo by Resemble AI, ~500 MB) and her ears, once, so she can talk and listen as
#      soon as she opens. Her ears are ONE model picked for this computer by moomu itself (`moomu --fetch-ears`: Parakeet
#      by NVIDIA, ~660 MB, or Moonshine, 140-270 MB, on a computer too small or slow for it)
# Run it again to update. To remove moomu:  curl -fsSL https://moomu.app/install | bash -s uninstall
set -euo pipefail
BUILDS="cdaz-dev/moomu-builds"
say() { printf '\033[1m%s\033[0m\n' "$*"; }

case "$(uname -s)" in
  Darwin) OS=mac; DATA="$HOME/Library/Application Support/moomu/moomu" ;;
  Linux)  OS=linux; DATA="${XDG_DATA_HOME:-$HOME/.local/share}/moomu/moomu"
          [ "$(uname -m)" = x86_64 ] || { echo "moomu for Linux is x86_64 only for now."; exit 1; } ;;
  *) echo "This installer is for macOS and Linux. On Windows, run in PowerShell:  irm https://moomu.app/install.ps1 | iex"; exit 1 ;;
esac
size() { if [ "$OS" = mac ]; then stat -f %z "$1" 2>/dev/null || echo 0; else stat -c %s "$1" 2>/dev/null || echo 0; fi; }
sum() { if [ "$OS" = mac ]; then shasum -a 256 "$1" | cut -d' ' -f1; else sha256sum "$1" | cut -d' ' -f1; fi; }
LBASE="${XDG_DATA_HOME:-$HOME/.local/share}"

# uninstall: moomu and what it downloaded go (the app, its voice and ears, its own Node, starting at login), as the
# Windows uninstaller does. Your brain folder, your projects and Claude Code (and its chats) are yours and stay
if [ "${1:-}" = "uninstall" ]; then
  say "removing moomu..."
  pkill -x moomu 2>/dev/null || true
  # its own computer (the VM, if it was set up): on Linux QEMU runs on its own, so it's stopped before its folder goes
  # (on a Mac it ran inside moomu and went with it)
  vmpid="$(cat "$LBASE/moomu/vm/qemu.pid" 2>/dev/null || true)"
  [ -n "$vmpid" ] && kill "$vmpid" 2>/dev/null && sleep 1 || true
  if [ "$OS" = mac ]; then
    rm -rf /Applications/moomu.app "$HOME/Library/Application Support/moomu" "$HOME/.moomu"
    rm -f "$HOME/Library/LaunchAgents/app.moomu.login.plist"
  else
    rm -rf "$LBASE/moomu" "$HOME/.moomu"
    rm -f "$HOME/.local/bin/moomu" "$LBASE/applications/moomu.desktop" "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/moomu.desktop"
  fi
  say "done (its own computer too, if it had one). Your brain folder, your projects and Claude Code are still here."
  exit 0
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# the newest release with a build for this system in it (MOOMU_BASE: another place to download from)
if [ "$OS" = mac ]; then asset=moomu-macos.zip; else asset=moomu-linux.AppImage; fi
if [ -n "${MOOMU_BASE:-}" ]; then
  url="$MOOMU_BASE/$asset"
else
  url="$(curl -fsSL "https://api.github.com/repos/$BUILDS/releases?per_page=30" \
        | grep -o "\"browser_download_url\": *\"[^\"]*/${asset//./\\.}\"" | head -1 | sed 's/.*"\(https[^"]*\)"$/\1/')"
fi
[ -n "$url" ] || { echo "Couldn't reach moomu's downloads. Check your connection and try again."; exit 1; }
build="$(printf '%s' "$url" | sed -n 's|.*/download/b\([0-9]*\)/.*|\1|p')"
say "downloading moomu${build:+ (build $build)}..."
curl -fL --progress-bar "$url" -o "$tmp/$asset"

pkill -x moomu 2>/dev/null || true
if [ "$OS" = mac ]; then
  say "installing to /Applications..."
  rm -rf "$tmp/app"; mkdir -p "$tmp/app"
  ditto -x -k "$tmp/$asset" "$tmp/app"
  rm -rf /Applications/moomu.app
  ditto "$tmp/app/moomu.app" /Applications/moomu.app
  xattr -dr com.apple.quarantine /Applications/moomu.app 2>/dev/null || true
else
  say "installing..."
  # one file, moomu's own folder; moomu updates it in place from then on
  app="$LBASE/moomu/moomu.AppImage"
  mkdir -p "$LBASE/moomu" "$HOME/.local/bin" "$LBASE/applications"
  cp "$tmp/$asset" "$app.new" && chmod +x "$app.new" && mv -f "$app.new" "$app"
  ln -sf "$app" "$HOME/.local/bin/moomu"
  (cd "$tmp" && APPIMAGE_EXTRACT_AND_RUN=1 "$app" --appimage-extract usr/share/icons/hicolor/1024x1024/apps/moomu.png >/dev/null 2>&1) \
    && cp "$tmp/squashfs-root/usr/share/icons/hicolor/1024x1024/apps/moomu.png" "$LBASE/moomu/moomu.png" || true
  cat > "$LBASE/applications/moomu.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=moomu
GenericName=AI assistant
Comment=Lives in your notch and works with your Claude Code (or Codex)
Exec="$app"
Icon=$LBASE/moomu/moomu.png
Terminal=false
Categories=Utility;
StartupNotify=false
DESKTOP
  # (its AppImage runtime opens it with fusermount3 or fusermount, no libfuse2 needed; without either it still opens
  # by unpacking itself each time, just slower)
  if ! command -v fusermount3 >/dev/null && ! command -v fusermount >/dev/null; then
    echo "(no FUSE here: moomu will start a little slower. Your package manager's fuse3 fixes that)"
  fi
fi

if ! command -v claude >/dev/null && [ ! -x "$HOME/.local/bin/claude" ]; then
  say "installing Claude Code (Anthropic's own installer)..."
  curl -fsSL https://claude.ai/install.sh | bash
fi
# Claude Code's installer puts it in ~/.local/bin, which a Mac's Terminal doesn't search ("command not found"):
# that folder goes on the path for zsh and bash, once
if [ "$OS" = mac ] && [ -x "$HOME/.local/bin/claude" ]; then
  for rc in "$HOME/.zshrc" "$HOME/.bash_profile"; do
    { [ "$rc" = "$HOME/.zshrc" ] || [ -f "$rc" ]; } || continue
    grep -qs '.local/bin' "$rc" || printf '\n# Claude Code (added by moomu'"'"'s installer)\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
  done
fi

# Node (moomu's browser runs on it): moomu's own copy if there's none, in ~/.moomu/node
if ! command -v npx >/dev/null && [ ! -x "$HOME/.moomu/node/bin/npx" ]; then
  say "installing Node for moomu's browser (its own copy)..."
  arch="$(uname -m)"; [ "$arch" = "x86_64" ] && arch="x64"
  [ "$OS" = mac ] && plat=darwin || plat=linux
  file="$(curl -fsSL https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt | awk '{print $2}' | grep "$plat-$arch.tar.gz$" | head -1)"
  if [ -n "$file" ]; then
    mkdir -p "$HOME/.moomu"
    curl -fsSL "https://nodejs.org/dist/latest-v22.x/$file" | tar -xz -C "$tmp"
    rm -rf "$HOME/.moomu/node"; mv "$tmp/${file%.tar.gz}" "$HOME/.moomu/node"
  else echo "(couldn't find Node for this computer: moomu will ask for it when its browser is first used)"; fi
fi

# her voice (Chatterbox Turbo, MIT, ~500 MB): downloaded now, once, so she can talk the moment she opens. Each file
# checked against its fingerprint; anything that fails is fetched by moomu itself when it starts
voice="$DATA/voice/turbo"
mkdir -p "$voice/onnx"
need=0
while read -r name size sha; do
  [ "$(size "$voice/$name")" = "$size" ] || need=1
done <<'FILES'
tokenizer.json 3562272 3f04e34bea22f9144d1a19151154095bc9ce0430bf421304f5797e716288a906
onnx/embed_tokens_q4.onnx 2844 fd6ba1d22902e8f539d3dd6d7c1c44b98ebb4c84ebbb5e47fcb826ddcf667561
onnx/embed_tokens_q4.onnx_data 37286384 f54a51e234b509b64c3a03bb79e1149fba7e2eba6c2d9c222f18883379e1f5d8
onnx/language_model_q4.onnx 274572 b39d03d3f8b943b9e60c6fce3fb41191dbc1df4589f913291db1e214eef669b1
onnx/language_model_q4.onnx_data 204456572 2c029dc0acf48752473d8c74c72b5ceaaad76b9886fe106eaf2022142d5b5d5e
onnx/conditional_decoder_q4.onnx 2179022 dccb7a6cea3472dc7f7d070eeb70ade18e6327fb4ec61a3d62cf211bfed90ea2
onnx/conditional_decoder_q4.onnx_data 246397384 b5c5317e0b79a1a19dd3d5e2b2091ea06b15716716ab801a54eaeb906c6971ec
FILES
if [ "$need" = 1 ]; then
  say "downloading its voice (about 500 MB, once)..."
  while read -r name size sha; do
    [ "$(size "$voice/$name")" = "$size" ] && continue
    if curl -fL --progress-bar "https://huggingface.co/ResembleAI/chatterbox-turbo-ONNX/resolve/d21799bd0354adb85e348b8a0442a8405110a2cf/$name" -o "$voice/$name.part" &&
       [ "$(sum "$voice/$name.part")" = "$sha" ]; then
      mv -f "$voice/$name.part" "$voice/$name"
    else rm -f "$voice/$name.part"; echo "(its voice will finish downloading when moomu opens)"; break; fi
  done <<'FILES'
tokenizer.json 3562272 3f04e34bea22f9144d1a19151154095bc9ce0430bf421304f5797e716288a906
onnx/embed_tokens_q4.onnx 2844 fd6ba1d22902e8f539d3dd6d7c1c44b98ebb4c84ebbb5e47fcb826ddcf667561
onnx/embed_tokens_q4.onnx_data 37286384 f54a51e234b509b64c3a03bb79e1149fba7e2eba6c2d9c222f18883379e1f5d8
onnx/language_model_q4.onnx 274572 b39d03d3f8b943b9e60c6fce3fb41191dbc1df4589f913291db1e214eef669b1
onnx/language_model_q4.onnx_data 204456572 2c029dc0acf48752473d8c74c72b5ceaaad76b9886fe106eaf2022142d5b5d5e
onnx/conditional_decoder_q4.onnx 2179022 dccb7a6cea3472dc7f7d070eeb70ade18e6327fb4ec61a3d62cf211bfed90ea2
onnx/conditional_decoder_q4.onnx_data 246397384 b5c5317e0b79a1a19dd3d5e2b2091ea06b15716716ab801a54eaeb906c6971ec
FILES
fi

# her ears: moomu looks at this computer (memory, the CPU, a second's speed test) and downloads the one model that suits
# it, the same code on every system (earsetup.cpp). Anything that fails is fetched by moomu itself when it opens
if [ "$OS" = mac ]; then
  /Applications/moomu.app/Contents/MacOS/moomu --fetch-ears || true
elif command -v fusermount3 >/dev/null || command -v fusermount >/dev/null; then
  "$LBASE/moomu/moomu.AppImage" --fetch-ears || true
else
  (cd "$tmp" && APPIMAGE_EXTRACT_AND_RUN=1 "$LBASE/moomu/moomu.AppImage" --fetch-ears) || true
fi

say "done. opening moomu ✦"
if [ "$OS" = mac ]; then open /Applications/moomu.app
else (setsid "$LBASE/moomu/moomu.AppImage" >/dev/null 2>&1 < /dev/null &) ; fi

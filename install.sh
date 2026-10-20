#!/usr/bin/env bash
# moomu, installed in one command (macOS and Linux):  curl -fsSL https://moomu.app/install | bash
#   1. downloads the newest moomu from moomu's public releases (github.com/cdaz-dev/moomu-builds)
#   2. macOS: puts moomu.app in /Applications (replacing an older one) and opens it. Linux: the AppImage in
#      ~/.local/share/moomu, moomu in your app menu and on your PATH (~/.local/bin/moomu), then opens it
#   3. installs Claude Code with Anthropic's own installer if it isn't there yet (you sign in to it in moomu's
#      first run, in Claude Code's own window: moomu never sees your login)
#   4. installs a private copy of Node for moomu's browser if there's none (in ~/.moomu, nothing system-wide)
#   5. downloads her voice (Chatterbox Turbo by Resemble AI, ~500 MB) and her ears (Moonshine, 136-257 MB), once, so
#      she can talk and listen as soon as she opens
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
  if [ "$OS" = mac ]; then
    rm -rf /Applications/moomu.app "$HOME/Library/Application Support/moomu" "$HOME/.moomu"
    rm -f "$HOME/Library/LaunchAgents/app.moomu.login.plist"
  else
    rm -rf "$LBASE/moomu" "$HOME/.moomu"
    rm -f "$HOME/.local/bin/moomu" "$LBASE/applications/moomu.desktop" "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/moomu.desktop"
  fi
  say "done. Your brain folder, your projects and Claude Code are still here."
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
GenericName=AI companion
Comment=A companion in your notch that works with your Claude Code (or Codex)
Exec="$app"
Icon=$LBASE/moomu/moomu.png
Terminal=false
Categories=Utility;
StartupNotify=false
DESKTOP
  # (an AppImage needs FUSE 2 to open as one file; without it, it still opens by unpacking itself each time)
  if ! ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
    echo "(no FUSE 2 here: moomu will start a little slower. Your package manager's libfuse2 / fuse2 fixes that)"
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
  say "downloading its voice and ears (about 650-750 MB, once)..."
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

# her ears (Moonshine, MIT): the medium model on a Mac with 16 GB or more, the small one below (as the app picks)
if [ "$OS" = mac ]; then mem="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"; else mem=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0) * 1024 )); fi
if [ "$mem" -ge 15032385536 ]; then ears=medium; else ears=small; fi
ed="$DATA/models/moonshine-$ears"
mkdir -p "$ed"
if [ "$ears" = medium ]; then list="$(cat <<'FILES'
adapter.ort 3651296 3f2a287def57cc094367a0eec3c4f5fc36a32ec420e86764b696920991b20281
cross_kv.ort 11643776 642f6e21cd305be79342207c6f9e6b681d469d55bc48c72b27b84846fb71fd1e
decoder_kv.ort 146972408 193bb366492b74fc4ad338c6778e8d8eb916aaa11b5aa264f9057f4db7759486
encoder.ort 94705376 12915e76ebac7dd287c5ea63965d06103a53ba1ce242a4a34f318f3958c60c37
frontend.model.ort 28720 95768855c70c8251eeecc05fedf69999da1b8ab16f605c9f457fd3354b0ad6b5
frontend.weights.ort 11889560 5ac941f490cbe035b335b99a414cc393d62d4c6f9f2423495b286870d271d709
streaming_config.json 513 28e83b7a28e91472692a035e0dae3116422ae43aeb2bef5ed822c44ce89b88af
tokenizer.bin 249974 6884b35fd6377d4c4d32336a0bc152f36b64d1e45b6503683cdc238250a8472d
FILES
)"; else list="$(cat <<'FILES'
adapter.ort 2870368 c665f742364febad597cc9ac1e0b341ffbee0e24a1466e2f3bde95e6e4771762
cross_kv.ort 5356536 e2d3417144e9514055ebfefe8dcc4c0a55a55adcb8530435844c75c53e352bf6
decoder_kv.ort 81878600 1a05465b1dd955858dfcbee039c0020fb5dd982b0f5094c34e61735d518d771b
encoder.ort 44148576 2d4d973e91e8aca08c51e7e7efa28a46ab265b63d809d5294d18b86bcd85b993
frontend.model.ort 26944 09b1210ae30dc5f0f3e45f0ebab914c254741323114f53fbbe5ae62cca35058f
frontend.weights.ort 7769464 7ef97521bd4bad3928f5bb6808586f4fcc6e92bd5990394112eed7d4052ec338
streaming_config.json 512 26f02b6afb22d60871a5efd85c3d38e569cc0ddb6c5eb6e93d3260152ae8a47a
tokenizer.bin 249974 6884b35fd6377d4c4d32336a0bc152f36b64d1e45b6503683cdc238250a8472d
FILES
)"; fi
printf '%s\n' "$list" | while read -r name size sha; do
  [ "$(size "$ed/$name")" = "$size" ] && continue
  if curl -fsSL "https://download.moonshine.ai/model/$ears-streaming-en/quantized_26_08_21/$name" -o "$ed/$name.part" &&
     [ "$(sum "$ed/$name.part")" = "$sha" ]; then
    mv -f "$ed/$name.part" "$ed/$name"
  else rm -f "$ed/$name.part"; echo "(its ears will finish downloading when moomu opens)"; break; fi
done

say "done. opening moomu ✦"
if [ "$OS" = mac ]; then open /Applications/moomu.app
else (setsid "$LBASE/moomu/moomu.AppImage" >/dev/null 2>&1 < /dev/null &) ; fi

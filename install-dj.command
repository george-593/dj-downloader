#!/bin/bash
# Installs the `dj` command: downloads songs as MP3s (with artwork + tags) into ~/Music/DJ.
# No Homebrew, no admin password. Everything lives in ~/.dj and can be removed by deleting it.
# DJ.app runs this automatically on first launch; it can also be run on its own:
#   curl -fsSL <raw-url-of-this-file> | bash
set -euo pipefail

# Bump when this script changes so DJ.app knows to re-run it
INSTALL_VERSION=2

DJ_HOME="$HOME/.dj"
BIN="$DJ_HOME/bin"
OUT_DIR="$HOME/Music/DJ"
ZSHRC="$HOME/.zshrc"

case "$(uname -m)" in
  arm64) FF_ARCH=arm64; DENO_ARCH=aarch64 ;;
  *)     FF_ARCH=amd64; DENO_ARCH=x86_64 ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() { curl -fL --progress-bar --retry 3 -o "$2" "$1"; }

echo "==> Installing dj into $DJ_HOME"
mkdir -p "$BIN" "$OUT_DIR"

# The folder build starts in ~0.2s; the single-file build unpacks itself on every run (~3s)
echo "==> Downloading yt-dlp"
fetch "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos.zip" "$TMP/yt-dlp.zip"
rm -rf "$DJ_HOME/yt-dlp"
ditto -x -k "$TMP/yt-dlp.zip" "$DJ_HOME/yt-dlp"
rm -f "$BIN/yt-dlp"
cat > "$BIN/yt-dlp" <<'EOF'
#!/bin/bash
exec "$(dirname "$0")/../yt-dlp/yt-dlp_macos" "$@"
EOF

echo "==> Downloading ffmpeg"
fetch "https://ffmpeg.martin-riedl.de/redirect/latest/macos/$FF_ARCH/release/ffmpeg.zip" "$TMP/ffmpeg.zip"
unzip -oq "$TMP/ffmpeg.zip" -d "$BIN"

echo "==> Downloading ffprobe"
fetch "https://ffmpeg.martin-riedl.de/redirect/latest/macos/$FF_ARCH/release/ffprobe.zip" "$TMP/ffprobe.zip"
unzip -oq "$TMP/ffprobe.zip" -d "$BIN"

# yt-dlp needs a JavaScript runtime to download from YouTube
echo "==> Downloading deno"
fetch "https://github.com/denoland/deno/releases/latest/download/deno-$DENO_ARCH-apple-darwin.zip" "$TMP/deno.zip"
unzip -oq "$TMP/deno.zip" -d "$BIN"

cat > "$BIN/dj" <<'EOF'
#!/bin/bash
# dj <link> [more links...]   download as MP3 into ~/Music/DJ
# dj                          asks for a link
# dj update                   update yt-dlp now (also happens automatically once a week)
BIN="$(cd "$(dirname "$0")" && pwd)"
export PATH="$BIN:$PATH"
STAMP="$BIN/.last-update"

if [ "${1:-}" = "update" ]; then
  yt-dlp -U && touch "$STAMP"
  exit
fi

# YouTube changes often and old yt-dlp versions stop working, so keep it fresh
if [ -z "$(find "$STAMP" -mtime -7 2>/dev/null)" ]; then
  yt-dlp -U >/dev/null 2>&1 && touch "$STAMP"
fi

if [ $# -eq 0 ]; then
  read -r -p "Paste a link: " url
  [ -n "$url" ] || exit 1
  set -- "$url"
fi

exec yt-dlp --ffmpeg-location "$BIN" \
  -x --audio-format mp3 --audio-quality 0 \
  --embed-thumbnail --embed-metadata \
  --parse-metadata "title:%(artist)s - %(title)s" \
  -P "$HOME/Music/DJ" -o "%(title)s.%(ext)s" \
  "$@"
EOF

chmod +x "$BIN"/* "$DJ_HOME/yt-dlp/yt-dlp_macos"
xattr -dr com.apple.quarantine "$DJ_HOME" 2>/dev/null || true
touch "$BIN/.last-update"

echo "==> Adding dj to your shell"
touch "$ZSHRC"
if ! grep -q '# >>> dj >>>' "$ZSHRC"; then
  cat >> "$ZSHRC" <<'EOF'

# >>> dj >>>
export PATH="$HOME/.dj/bin:$PATH"
alias dj='noglob dj'
# <<< dj <<<
EOF
fi

echo "==> Checking it works"
"$BIN/yt-dlp" --version >/dev/null
"$BIN/ffmpeg" -version >/dev/null
"$BIN/deno" --version >/dev/null
echo "$INSTALL_VERSION" > "$DJ_HOME/.version"

echo
echo "All done! Open a NEW Terminal window and type:"
echo "    dj https://www.youtube.com/watch?v=..."
echo "or just 'dj' and paste the link. Songs go to ~/Music/DJ."

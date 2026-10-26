# DJ

A tiny Mac app: paste a YouTube or SoundCloud link, get a high-quality MP3 (V0) with cover art and
artist/title tags in **Music › DJ**, ready to drop into rekordbox, Serato, djay or Mixxx.

## Install

Friendly step-by-step guide: **https://dj.georges.codes**

1. **[Download DJ.zip](https://github.com/george-593/dj-downloader/releases/latest/download/DJ.zip)**
2. Open your **Downloads** folder and double-click **DJ.zip** (Safari may already have done this).
   Drag **DJ** into **Applications**.
3. Open **DJ**. Your Mac will say *"Apple could not verify 'DJ' is free of malware"*. Click **Done**.
   This happens because DJ isn't from the App Store, not because anything is wrong.
4. Open **System Settings → Privacy & Security**, scroll down to **Security**, and next to
   *"DJ was blocked to protect your Mac"* click **Open Anyway**. Enter your Mac password (or use
   Touch ID), then click **Open Anyway** again.
5. DJ spends about a minute setting itself up the first time. After that it opens straight away.

You only do steps 3 and 4 once.

## Use it

1. Copy a link from YouTube or SoundCloud.
2. Open DJ. The link is already filled in. Click **Download**.
3. Click **Show in Finder** to see the song. Everything goes into **Music › DJ**.

Playlist links download the whole playlist. You can also paste several links at once, separated by spaces.

## If something goes wrong

- **"Download failed"**: check the link opens in your browser, then quit DJ and open it again.
  DJ updates its downloader once a week; YouTube changes often and an update usually fixes it.
- **Uninstall**: delete DJ from Applications, then in Finder press **⇧⌘G**, type `~/.dj` and delete that folder.
  Your songs in Music › DJ stay put.

## For developers

- `install-dj.command` downloads yt-dlp, ffmpeg/ffprobe and deno into `~/.dj` and writes the `dj`
  command (also usable from Terminal). The app runs it on first launch; it also works on its own.
- `DJ.swift` is the SwiftUI app that drives `~/.dj/bin/dj` and shows progress.
- `./build.sh` builds a universal `build/DJ.app` and `build/DJ.zip` (needs Xcode Command Line Tools).
  Bump `INSTALL_VERSION` in both `install-dj.command` and `DJ.swift` when the installer changes,
  so existing users get re-set-up.
- `docs/` is the install guide at dj.georges.codes (GitHub Pages, deploys on push to main).

# Distribution

Sessions is free and ships without an Apple Developer ID: an ad-hoc signed DMG on GitHub Releases, and a cask in our own Homebrew tap.

## Why this setup

- **No Mac App Store.** The store requires the App Sandbox, and Sessions has to write hooks into `~/.claude/settings.json`, start the `claude` CLI and listen on a unix socket in the home folder.
- **No official `homebrew/cask`.** Since Homebrew 5 the official tap only accepts signed and notarized apps, which needs the $99/year Apple Developer Program.
- **Own tap works.** A third-party tap can ship an unsigned app. The cask removes the download quarantine after install, so Homebrew users never see the Gatekeeper block. Newer Homebrew may ask users to `brew trust` the tap once.
- **DMG users see one warning.** On first launch macOS blocks the app; they click **Open Anyway** in System Settings → Privacy & Security. Since macOS 15 the old right-click → Open shortcut no longer works.

## One-time setup

1. Create two public GitHub repositories:
   - `ilsrbn/serbin-sessions` for this code.
   - `ilsrbn/homebrew-tap` for the cask. The `homebrew-` prefix is what makes `brew install ilsrbn/tap/…` work.
2. Push this repo, clone the tap next to it, and sign in to the GitHub CLI:
   ```sh
   git remote add origin git@github.com:ilsrbn/serbin-sessions.git && git push -u origin main
   git clone git@github.com:ilsrbn/homebrew-tap.git ../homebrew-tap
   gh auth login
   ```
3. On GitHub, set **Settings → General → Social preview** to `assets/readme/social-preview.png`.

## Each release

1. Bump `CFBundleShortVersionString` in `scripts/bundle.sh` and add a section to `CHANGELOG.md` (`## 0.2.0 · <date>`).
2. Commit, then run:
   ```sh
   TAP_DIR=../homebrew-tap PUBLISH=1 ./scripts/release.sh
   ```
   This builds `build/SerbinSessions-<version>.dmg`, updates `packaging/homebrew/serbin-sessions.rb` with the new version and SHA-256, creates the GitHub Release with the changelog section as notes, and pushes the cask to the tap.
3. Commit the updated cask in this repo too.

Without `PUBLISH=1` the script only builds the DMG and updates the cask, so you can check the image first.

## Notes

- **Apple silicon only.** Every Mac with a notch is Apple silicon, so the cask declares `depends_on arch: :arm64` and the build is native arm64.
- **Hooks point at `/Applications/Serbin Sessions.app`.** Both the DMG and the cask install there; don't change the app name.
- **Uninstall.** `brew uninstall serbin-sessions` runs `notch-hook uninstall` first, so Claude Code's settings are cleaned up. `brew uninstall --zap` also removes `~/.serbin-sessions`.
- **Updates.** For now users update with `brew upgrade` or a new download. In-app updates (Sparkle) can come later.
- **If notarization is ever wanted**, the only changes are signing with a Developer ID plus hardened runtime, running `xcrun notarytool submit … --wait` and `xcrun stapler staple` on the DMG, and dropping the cask's quarantine `postflight`. After that the app can go to the official `homebrew/cask` too.

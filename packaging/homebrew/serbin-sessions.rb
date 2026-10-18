# Cask for the ilsrbn/homebrew-tap repository (Casks/serbin-sessions.rb).
# scripts/release.sh fills in version and sha256.
cask "serbin-sessions" do
  version "0.1.0"
  sha256 "d95376430faf7c5e42df0cd9ebd23c7ec8e309316b19276d9f91cba803d72cbd"

  url "https://github.com/ilsrbn/serbin-sessions/releases/download/v#{version}/SerbinSessions-#{version}.dmg"
  name "Serbin Sessions"
  desc "Notch panel for Claude Code sessions"
  homepage "https://github.com/ilsrbn/serbin-sessions"

  # Every Mac with a notch is Apple silicon.
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Serbin Sessions.app"

  # Not notarized: drop the download quarantine so Gatekeeper does not block the first launch.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Serbin Sessions.app"],
                          writable_paths: ["Serbin Sessions.app"], writable_base: :appdir
  end

  # Take our hooks out of ~/.claude/settings.json before the app goes away.
  uninstall_preflight_steps do
    run "Serbin Sessions.app/Contents/MacOS/notch-hook",
        base:           :appdir,
        args:           ["uninstall"],
        must_succeed:   false,
        writable_paths: [".claude"],
        writable_base:  :home
  end

  uninstall quit: "dev.ilsrbn.serbin-sessions"

  zap trash: "~/.serbin-sessions"
end

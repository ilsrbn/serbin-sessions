# Cask for the ilsrbn/homebrew-tap repository (Casks/serbin-sessions.rb).
# scripts/release.sh fills in version and sha256.
cask "serbin-sessions" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/ilsrbn/serbin-sessions/releases/download/v#{version}/SerbinSessions-#{version}.dmg"
  name "Serbin Sessions"
  desc "Notch panel for Claude Code sessions"
  homepage "https://github.com/ilsrbn/serbin-sessions"

  # Every Mac with a notch is Apple silicon.
  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "Serbin Sessions.app"

  # Not notarized: drop the download quarantine so Gatekeeper does not block the first launch.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Serbin Sessions.app"]
  end

  # Take our hooks out of ~/.claude/settings.json before the app goes away.
  uninstall_preflight do
    system_command "#{appdir}/Serbin Sessions.app/Contents/MacOS/notch-hook",
                   args: ["uninstall"], must_succeed: false
  end

  uninstall quit: "dev.ilsrbn.serbin-sessions"

  zap trash: "~/.serbin-sessions"
end

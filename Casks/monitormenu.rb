# Created: 2026-10-30 09:50 -05:00 · Edited: 2026-10-30 09:50 -05:00
# C6: Homebrew cask. Tap this repository, then `brew install --cask monitormenu`.
# `scripts/release.sh --update-cask` writes version and sha256; do not edit those two lines by hand.
cask "monitormenu" do
  version "1.0.1"
  sha256 "b6d71f10e3437fa5378f3bd6b5fc9b3cd9be423c12fe48974cabbb587614da41"

  url "https://github.com/martin-gleason/monitormenu/releases/download/v#{version}/MonitorMenu-#{version}.dmg"
  name "MonitorMenu"
  desc "Menu bar DDC/CI control for external monitors: inputs, brightness, PiP"
  homepage "https://github.com/martin-gleason/monitormenu"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "MonitorMenu.app"
  binary "#{appdir}/MonitorMenu.app/Contents/MacOS/monitorctl"

  uninstall quit: "dev.marty.MonitorMenu"

  zap trash: "~/Library/Preferences/dev.marty.MonitorMenu.plist"
end

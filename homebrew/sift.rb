cask "sift" do
  version "3.2.0"
  sha256 "5ba35fde0b60a645d61edacc8a8b8f198625ea91ac3750c60d41efe22a240a50"

  url "https://github.com/BadryansahBangsawan/Sift/releases/download/v#{version}/Sift-#{version}.zip"
  name "Sift"
  desc "Free, open-source macOS app manager and system cleaner"
  homepage "https://github.com/BadryansahBangsawan/Sift"

  depends_on macos: :ventura

  app "Sift.app"

  # Refresh LaunchServices so the Dock/Launchpad icon updates immediately on
  # (re)install instead of showing a stale cached icon (issue #111).
  postflight_steps do
    run "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister",
        args: ["-f", "{{appdir}}/Sift.app"]
  end

  # Sift was called PureMac before; the legacy paths clean up an upgraded install.
  zap trash: [
    "~/Library/Application Support/Sift",
    "~/Library/Preferences/com.sift.app.plist",
    "~/Library/Caches/com.sift.app",
    "~/Library/LaunchAgents/com.sift.scheduler.plist",
    "~/Library/Application Support/PureMac",
    "~/Library/Preferences/com.puremac.app.plist",
    "~/Library/Caches/com.puremac.app",
    "~/Library/LaunchAgents/com.puremac.scheduler.plist",
  ]
end

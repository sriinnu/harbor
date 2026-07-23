cask "harbor" do
  version "0.1.0-alpha"
  sha256 :no_check  # TODO: Replace with actual SHA256 after first release

  url "https://github.com/sriinnu/harbor/releases/download/v#{version}/Harbor-#{version}.dmg"
  name "Harbor"
  desc "GitHub menubar app - Your GitHub work, safely docked"
  homepage "https://github.com/sriinnu/harbor"

  # Requires macOS 15.0 (Sequoia) or later
  depends_on macos: ">= :sequoia"

  app "Harbor.app"

  # Custom uninstall to remove app data
  zap trash: [
    "~/Library/Application Support/com.sriinnu.harbor",
    "~/Library/Caches/com.sriinnu.harbor",
    "~/Library/Preferences/com.sriinnu.harbor.plist",
    "~/Library/Saved Application State/com.sriinnu.harbor.savedState",
  ]

  # Post-install message
  caveats <<~EOS
    Harbor is a menubar application. To run it:
    1. Open Applications folder
    2. Launch Harbor
    3. Look for the Harbor icon in your menubar

    The app will continue running in the background. You can access it
    from the menubar at any time.
  EOS
end

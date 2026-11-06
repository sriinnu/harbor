cask "harbor" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/sriinnu/harbor/releases/download/v#{version}/Harbor-#{version}.zip"
  name "Harbor"
  desc "Menu-bar view of what needs you across GitHub, GitLab, Azure DevOps and local Git"
  homepage "https://github.com/sriinnu/harbor"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sequoia

  app "Harbor.app"
  binary "#{appdir}/Harbor.app/Contents/Helpers/harborcli"

  zap trash: [
    "~/Library/Application Support/com.sriinnu.harbor",
    "~/Library/Caches/com.sriinnu.harbor",
    "~/Library/HTTPStorages/com.sriinnu.harbor",
    "~/Library/Preferences/com.sriinnu.harbor.plist",
  ]
end

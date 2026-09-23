cask "copilot-aic-menu" do
  version "0.1.0"
  sha256 "6aa5560da9b918fd0d85c8c9ec9ca80af7baa94e21bd582996337d97a5477f37"

  url "https://github.com/snaveevans/copilot-aic-menu/releases/download/v0.1.0/CopilotAICMenu-macos-universal.zip"
  name "Copilot AIC Menu"
  desc "Copilot AI credit usage in the macOS menu bar"
  homepage "https://github.com/snaveevans/copilot-aic-menu"

  depends_on macos: :ventura
  depends_on formula: "gh"

  app "CopilotAICMenu.app"

  caveats <<~EOS
    Sign in with GitHub CLI: gh auth login
    Launch the app: open /Applications/CopilotAICMenu.app
    Unnotarized releases may require approval in System Settings > Privacy & Security.
  EOS
end

#!/usr/bin/env ruby
# Generate a pinned Homebrew cask for the tagged GitHub Release archive.
repo, version, sha = ARGV
abort "Usage: #{$PROGRAM_NAME} OWNER/REPO X.Y.Z SHA256" unless ARGV.length == 3
abort "Invalid GitHub repository" unless repo.match?(/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/)
abort "Invalid version" unless version.match?(/\A\d+\.\d+\.\d+\z/)
abort "Invalid SHA-256" unless sha.match?(/\A[0-9a-fA-F]{64}\z/)

puts <<~CASK
  cask "copilot-aic-menu" do
    version "#{version}"
    sha256 "#{sha.downcase}"

    url "https://github.com/#{repo}/releases/download/v#{version}/CopilotAICMenu-macos-universal.zip"
    name "Copilot AIC Menu"
    desc "Copilot AI credit usage in the macOS menu bar"
    homepage "https://github.com/#{repo}"

    depends_on macos: :ventura
    depends_on formula: "gh"

    app "CopilotAICMenu.app"

    caveats <<~EOS
      Sign in with GitHub CLI: gh auth login
      Launch the app: open /Applications/CopilotAICMenu.app
      Unnotarized releases may require approval in System Settings > Privacy & Security.
    EOS
  end
CASK

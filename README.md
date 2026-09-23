# Copilot AI credits in the macOS menu bar

A native menu-bar app showing the **percentage of Copilot AI credits used this cycle** as `AIC 22.9%`. The dropdown shows the used/total and remaining credits, reset date, account, update time, and data source. It refreshes every 15 minutes, on wake, or via **Refresh Now**.

## Screenshots

Menu bar:

![AIC 22.9% in the macOS menu bar](docs/images/menu_bar.png)

Expanded menu (credit counts, account name, and timestamps are irreversibly obscured; the percent is visible):

<img src="docs/images/expanded_menu.png" alt="Expanded Copilot AIC menu with private values obscured" width="520">

## Set up (recommended for organization-managed Copilot)

1. Install [GitHub CLI](https://cli.github.com/) and sign into the GitHub account that uses Copilot: `gh auth login`. Check with `gh auth status`.
2. With Apple's Command Line Tools installed, run:
   ```sh
   ./scripts/build-app.sh
   open dist/CopilotAICMenu.app
   ```
3. The default **Copilot quota (gh)** source needs no additional token. It calculates **(entitlement − remaining) ÷ entitlement × 100**, displayed as percent **used**. This works for an organization-managed seat without organization billing-admin permissions. It does **not** use the `credits_used` field, which is not the current-cycle total.

**Important:** The quota response is from GitHub's **undocumented `/copilot_internal/user` endpoint** using your existing `gh` login. The app does not read or store the CLI's OAuth token itself, but this endpoint could change or stop working. The menu shows an error instead of a guessed zero if it does. It never runs an AI prompt to check usage.

## Other sources

The menu also offers documented GitHub billing report endpoints:

- **Use Personal Billing:** Requires a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) with **User permissions → Plan → Read-only**. This shows only AI credits **billed directly to your personal account**, not those managed by an organization/enterprise.
- **Use Organization Billing…:** Enter the organization paying for your Copilot seat. Requires organization billing/admin access and a token with **Organization permissions → Administration → Read-only**. The report is filtered to your GitHub username. An enterprise-billed seat may require a separate enterprise billing API instead.

For these sources, use **Set GitHub Token…** and paste with ⌘V or **Paste from Clipboard**. The token is stored in macOS Keychain. **Remove Token…** deletes it. A billing report with no matching Copilot AI credit lines shows an explanation, not a fabricated zero. Billing reports may lag behind the quota shown in GitHub's UI. **Billing-only sources have no allowance/remaining value, so they still show a count rather than a percentage**; select the quota source for percent used.

To start at login, add `dist/CopilotAICMenu.app` in **System Settings → General → Login Items** and keep the app at that path. Requires macOS 13 or newer. Run offline checks with `swift run AICCoreChecks`, or verify the live quota from your `gh` login with `swift run AICCoreChecks --live`. No Xcode project or third-party Swift dependencies are needed.

The raw screenshots in the project root are ignored by Git. To regenerate the publishable copies under `docs/images/`, install Pillow and run `python3 scripts/redact-screenshots.py`; inspect the output before committing if the screenshots change.

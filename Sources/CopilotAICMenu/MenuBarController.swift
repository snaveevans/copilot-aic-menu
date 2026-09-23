import AppKit
import AICCore

private enum UsageSource: Equatable {
    case quota
    case personal
    case organization(String)
}

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    private let store = TokenStore()
    private let client = GitHubClient()
    private let quotaClient = CopilotQuotaClient()
    private var statusItem: NSStatusItem!
    private let summaryItem = NSMenuItem(title: "Used this cycle: — AIC", action: nil, keyEquivalent: "")
    private let remainingItem = NSMenuItem(title: "Remaining: — AIC", action: nil, keyEquivalent: "")
    private let accountItem = NSMenuItem(title: "GitHub account: —", action: nil, keyEquivalent: "")
    private let updatedItem = NSMenuItem(title: "Add a GitHub token to start.", action: nil, keyEquivalent: "")
    private let sourceItem = NSMenuItem(title: "Source: Copilot quota (gh)", action: nil, keyEquivalent: "")
    private let quotaItem = NSMenuItem(title: "Use Copilot Quota (gh)", action: #selector(useCopilotQuota), keyEquivalent: "")
    private let personalItem = NSMenuItem(title: "Use Personal Billing", action: #selector(usePersonalBilling), keyEquivalent: "")
    private let organizationItem = NSMenuItem(title: "Use Organization Billing…", action: #selector(useOrganizationBilling), keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
    private let tokenItem = NSMenuItem(title: "Set GitHub Token…", action: #selector(setToken), keyEquivalent: "")
    private let removeItem = NSMenuItem(title: "Remove Token…", action: #selector(removeToken), keyEquivalent: "")
    private var timer: Timer?
    private var source: UsageSource = {
        switch UserDefaults.standard.string(forKey: "usageSource") {
        case "personal": return .personal
        case "organization":
            if let org = UserDefaults.standard.string(forKey: "billingOrganization") {
                return .organization(org)
            }
            return .quota
        default: return .quota
        }
    }()
    private var username: String?
    private var latest: (month: BillingMonth, amount: Decimal)?
    private var quotaLimit: Decimal?
    private var quotaRemaining: Decimal?
    private var quotaPercent: Decimal?
    private var quotaReset: String?
    private var lastUpdated: Date?
    private var lastError: String?
    private var hasToken = false
    private var isRefreshing = false
    private var generation = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installEditMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        for item in [summaryItem, remainingItem, accountItem, sourceItem, updatedItem] {
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for item in [refreshItem, tokenItem, removeItem] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for item in [quotaItem, personalItem, organizationItem] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let billingItem = NSMenuItem(title: "Open GitHub Billing", action: #selector(openBilling), keyEquivalent: "")
        billingItem.target = self
        menu.addItem(billingItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        updateMenu()

        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.startRefresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refreshAfterWake), name: NSWorkspace.didWakeNotification, object: nil
        )
        startRefresh()
    }

    // A menu-bar-only app does not get the usual Edit menu automatically. Without
    // a Paste key equivalent, ⌘V can be swallowed while the token alert is open.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSTextView.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSTextView.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func startRefresh() {
        let month = BillingMonth.current()
        if latest?.month != month {
            latest = nil
            quotaLimit = nil
            quotaRemaining = nil
            quotaPercent = nil
            quotaReset = nil
            lastUpdated = nil
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        updateMenu()
        let currentGeneration = generation
        Task { await fetch(month: month, source: source, generation: currentGeneration) }
    }

    private func fetch(month: BillingMonth, source: UsageSource, generation: Int) async {
        do {
            if source == .quota {
                let quota = try await quotaClient.fetch()
                guard generation == self.generation else { return }
                isRefreshing = false
                if month != BillingMonth.current() {
                    startRefresh()
                    return
                }
                guard let used = quota.used else { throw CopilotQuotaError.unavailable }
                username = quota.login
                latest = (month, used)
                quotaLimit = quota.entitlement
                quotaRemaining = quota.remaining
                quotaPercent = quota.percentUsed
                quotaReset = quota.reset
                lastUpdated = Date()
                lastError = nil
                updateMenu()
                return
            }
            guard let token = try store.load(), !token.isEmpty else {
                guard generation == self.generation else { return }
                hasToken = false
                lastError = "Add a GitHub token to start."
                isRefreshing = false
                updateMenu()
                return
            }
            guard generation == self.generation else { return }
            hasToken = true
            let login: String
            if let username {
                login = username
            } else {
                login = try await client.login(token: token)
            }
            guard generation == self.generation else { return }
            username = login
            let billingSource: BillingSource
            switch source {
            case .personal: billingSource = .personal
            case .organization(let org): billingSource = .organization(org)
            case .quota: return // handled above
            }
            let report = try await client.credits(token: token, login: login, month: month, source: billingSource)
            guard generation == self.generation else { return }
            isRefreshing = false
            // Don't display the previous month's number if the request straddled midnight UTC.
            if month != BillingMonth.current() {
                startRefresh()
                return
            }
            guard let amount = report.copilotAICs else {
                lastError = switch source {
                case .personal: "No personal-billed credits reported. Organization/enterprise usage is excluded."
                case .organization: "No org-billed Copilot credits found for @\(login). Check the billing owner."
                case .quota: "No Copilot quota returned."
                }
                updateMenu()
                return
            }
            latest = (month, amount)
            lastUpdated = Date()
            lastError = nil
        } catch {
            guard generation == self.generation else { return }
            isRefreshing = false
            if case GitHubAPIError.http(403) = error {
                lastError = switch source {
                case .personal: "Access denied. Token needs user Plan: read."
                case .organization: "Org billing access denied. Requires org Administration: read and admin access."
                case .quota: "Copilot quota access denied. Check `gh auth status`."
                }
            } else {
                lastError = error.localizedDescription
            }
        }
        updateMenu()
    }

    private func updateMenu() {
        let amount = latest?.amount
        let count = amount.map(Self.format) ?? "—"
        let percent = quotaPercent.map(Self.formatPercent)
        if lastError != nil && (source == .quota || hasToken) {
            statusItem.button?.title = "AIC !"
        } else if source == .quota {
            statusItem.button?.title = percent.map { "AIC \($0)" } ?? (isRefreshing ? "AIC …" : "AIC —")
        } else {
            statusItem.button?.title = amount.map { "AIC \(Self.format($0))" } ?? (isRefreshing ? "AIC …" : "AIC —")
        }
        statusItem.button?.toolTip = source == .quota
            ? "Copilot AI credits used this cycle: \(percent ?? "—")"
            : "Copilot AI credits used this month (UTC)"
        remainingItem.isHidden = source != .quota
        if source == .quota {
            let limit = quotaLimit.map(Self.format) ?? "—"
            let remaining = quotaRemaining.map(Self.format) ?? "—"
            summaryItem.title = lastError != nil && amount != nil
                ? "Last known this cycle: \(count) / \(limit) AIC (\(percent ?? "—") used)"
                : "Used this cycle: \(count) / \(limit) AIC (\(percent ?? "—") used)"
            remainingItem.title = "Remaining: \(remaining) AIC"
        } else {
            summaryItem.title = lastError != nil && amount != nil
                ? "Last known this month (UTC): \(count) AIC"
                : "This month (UTC): \(count) AIC"
        }
        accountItem.title = username.map { "GitHub account: @\($0)" } ?? "GitHub account: —"
        sourceItem.title = switch source {
        case .quota: "Source: Copilot quota (gh; unofficial API)"
        case .personal: "Source: Personal billing"
        case .organization(let org): "Source: Organization @\(org)"
        }
        quotaItem.isEnabled = source != .quota
        personalItem.isEnabled = source != .personal
        organizationItem.title = switch source {
        case .organization: "Change Organization…"
        default: "Use Organization Billing…"
        }
        if let lastError {
            updatedItem.title = "Error: \(lastError)"
        } else if isRefreshing {
            updatedItem.title = "Refreshing…"
        } else if let lastUpdated {
            let time = lastUpdated.formatted(date: .omitted, time: .shortened)
            updatedItem.title = quotaReset.map { "Updated: \(time) · Resets: \($0)" } ?? "Updated: \(time)"
        } else {
            updatedItem.title = source == .quota ? "Sign in with `gh auth login` to start." : "Add a GitHub token to start."
        }
        refreshItem.isEnabled = !isRefreshing && (source == .quota || hasToken)
        removeItem.isEnabled = hasToken
        tokenItem.isEnabled = source != .quota
        tokenItem.title = hasToken ? "Replace GitHub Token…" : "Set GitHub Token…"
    }

    private static func format(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }

    private static func formatPercent(_ percent: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let value = formatter.string(from: NSDecimalNumber(decimal: percent)) ?? "\(percent)"
        return "\(value)%"
    }

    @objc private func refreshNow(_ sender: Any?) { startRefresh() }
    @objc private func refreshAfterWake(_ notification: Notification) { startRefresh() }

    @objc private func setToken(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "GitHub fine-grained token"
        alert.informativeText = "Create a personal access token with user permission Plan: read. It is stored in your Mac's Keychain. No repository access is needed."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let input = TokenInputView()
        alert.accessoryView = input
        alert.window.initialFirstResponder = input.field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let token = input.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        do {
            try store.save(token)
            generation += 1
            isRefreshing = false
            hasToken = true
            username = nil
            latest = nil
            lastUpdated = nil
            startRefresh()
        } catch {
            showError(error)
        }
    }

    @objc private func useCopilotQuota(_ sender: Any?) {
        UserDefaults.standard.set("quota", forKey: "usageSource")
        source = .quota
        sourceChanged()
    }

    @objc private func usePersonalBilling(_ sender: Any?) {
        UserDefaults.standard.set("personal", forKey: "usageSource")
        source = .personal
        sourceChanged()
    }

    @objc private func useOrganizationBilling(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Organization billing source"
        alert.informativeText = "Enter the GitHub organization paying for your Copilot seat. This API requires organization billing/admin access and a token with Organization Administration: read."
        alert.addButton(withTitle: "Use Organization")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 370, height: 24))
        field.placeholderString = "organization-name"
        field.stringValue = UserDefaults.standard.string(forKey: "billingOrganization") ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let org = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !org.isEmpty,
              org.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil
        else {
            showError(GitHubAPIError.invalidOrganization)
            return
        }
        UserDefaults.standard.set(org, forKey: "billingOrganization")
        UserDefaults.standard.set("organization", forKey: "usageSource")
        source = .organization(org)
        sourceChanged()
    }

    private func sourceChanged() {
        generation += 1
        isRefreshing = false
        latest = nil
        quotaLimit = nil
        quotaRemaining = nil
        quotaPercent = nil
        quotaReset = nil
        username = nil
        lastUpdated = nil
        lastError = nil
        startRefresh()
    }

    @objc private func removeToken(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Remove the GitHub token from Keychain?"
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try store.remove()
            generation += 1
            isRefreshing = false
            hasToken = false
            username = nil
            latest = nil
            lastUpdated = nil
            lastError = nil
            updateMenu()
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not save settings"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    @objc private func openBilling(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://github.com/settings/billing")!)
    }

    @objc private func quit(_ sender: Any?) { NSApp.terminate(nil) }
}

@main
struct CopilotAICMenu {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let controller = MenuBarController()
        app.delegate = controller
        app.run()
    }
}

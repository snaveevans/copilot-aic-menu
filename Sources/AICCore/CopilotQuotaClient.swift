import Foundation

// GitHub's Copilot UI uses a quota snapshot, which is separate from its
// documented billing reports. This response is not a public, stable REST API.
public struct CopilotQuota: Decodable {
    public let login: String
    public let reset: String?
    public let entitlement: Decimal
    public let remaining: Decimal
    public let tokenBasedBilling: Bool?
    public let hasQuota: Bool?

    enum CodingKeys: String, CodingKey {
        case login, reset, entitlement, remaining
        case tokenBasedBilling = "token_based_billing"
        case hasQuota = "has_quota"
    }

    public var used: Decimal? {
        guard entitlement > 0, hasQuota != false, tokenBasedBilling != false,
              remaining <= entitlement else { return nil }
        // `credits_used` in the response is NOT the current-cycle total.
        return entitlement - remaining
    }

    public var percentUsed: Decimal? {
        guard let used else { return nil }
        return used * 100 / entitlement
    }
}

public enum CopilotQuotaError: Error, LocalizedError {
    case missingGitHubCLI
    case requestFailed
    case invalidResponse
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .missingGitHubCLI:
            return "Install GitHub CLI (gh) to read your Copilot quota."
        case .requestFailed:
            return "Could not read Copilot quota. Check `gh auth status` in Terminal."
        case .invalidResponse:
            return "GitHub changed its Copilot quota response. Use a billing source instead."
        case .unavailable:
            return "No AI credit quota was returned for this GitHub account."
        }
    }
}

public struct CopilotQuotaClient {
    public init() {}

    public func fetch() async throws -> CopilotQuota {
        // Process.waitUntilExit is blocking, so never run it on AppKit's main actor.
        try await Task.detached(priority: .utility) { try Self.run() }.value
    }

    private static func run() throws -> CopilotQuota {
        let paths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"] +
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/gh" }
        guard let path = paths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw CopilotQuotaError.missingGitHubCLI
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        // Project only the fields needed for the menu. gh handles its own
        // authentication; no OAuth token is passed to or stored by this app.
        process.arguments = [
            "api", "/copilot_internal/user", "--jq",
            "{login: .login, reset: .quota_reset_date, entitlement: .quota_snapshots.premium_interactions.entitlement, remaining: .quota_snapshots.premium_interactions.quota_remaining, token_based_billing: .quota_snapshots.premium_interactions.token_based_billing, has_quota: .quota_snapshots.premium_interactions.has_quota}"
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw CopilotQuotaError.requestFailed }

        let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        watchdog.schedule(deadline: .now() + 25)
        watchdog.setEventHandler { if process.isRunning { process.terminate() } }
        watchdog.resume()
        defer { watchdog.cancel() }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CopilotQuotaError.requestFailed }
        guard let quota = try? JSONDecoder().decode(CopilotQuota.self, from: data),
              !quota.login.isEmpty else { throw CopilotQuotaError.invalidResponse }
        guard quota.used != nil else { throw CopilotQuotaError.unavailable }
        return quota
    }
}

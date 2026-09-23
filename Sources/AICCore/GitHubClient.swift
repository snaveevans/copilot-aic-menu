import Foundation

public struct BillingMonth: Equatable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    // GitHub's billing periods are calendar months in UTC.
    public static func current(at date: Date = Date()) -> BillingMonth {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month], from: date)
        return BillingMonth(year: parts.year!, month: parts.month!)
    }
}

public enum BillingSource: Equatable {
    case personal
    case organization(String)
}

public struct BillingReport: Decodable {
    public let usageItems: [UsageItem]

    public struct UsageItem: Decodable {
        public let product: String
        public let sku: String?
        public let unitType: String
        public let grossQuantity: Decimal

        var isCopilotAIC: Bool {
            let copilot = product.localizedCaseInsensitiveContains("Copilot") ||
                (sku?.localizedCaseInsensitiveContains("Copilot") ?? false)
            let aiCreditUnit = unitType.caseInsensitiveCompare("ai-credits") == .orderedSame ||
                (unitType.caseInsensitiveCompare("credits") == .orderedSame &&
                 (sku?.localizedCaseInsensitiveContains("AI Credit") ?? false))
            return copilot && aiCreditUnit
        }
    }

    // A report with no matching line items is ambiguous: it may mean zero usage
    // or that GitHub billed a different account. Never display it as a measured 0.
    public var copilotAICs: Decimal? {
        let items = usageItems.filter(\.isCopilotAIC)
        guard !items.isEmpty else { return nil }
        // Count credits consumed, including credits discounted from the bill.
        return items.reduce(Decimal.zero) { $0 + $1.grossQuantity }
    }
}

public enum GitHubAPIError: Error, LocalizedError {
    case unexpectedResponse
    case invalidLogin
    case invalidOrganization
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            return "GitHub returned an unexpected response."
        case .invalidLogin:
            return "GitHub returned an invalid username."
        case .invalidOrganization:
            return "Enter a valid GitHub organization name."
        case .http(401):
            return "Token rejected or expired. Replace your GitHub token."
        case .http(403):
            return "Billing access denied. Check the token's permissions and your account's billing access."
        case .http(404):
            return "AI credit usage is unavailable for this account or token."
        case .http(429):
            return "GitHub rate limit reached. Try again later."
        case .http(let code):
            return "GitHub returned HTTP \(code)."
        }
    }
}

public final class GitHubClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func login(token: String) async throws -> String {
        struct Profile: Decodable { let login: String }
        let profile: Profile = try await get("/user", token: token)
        guard !profile.login.isEmpty,
              profile.login.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil
        else { throw GitHubAPIError.invalidLogin }
        return profile.login
    }

    public func credits(
        token: String, login: String, month: BillingMonth, source: BillingSource = .personal
    ) async throws -> BillingReport {
        var query = [
            URLQueryItem(name: "year", value: String(month.year)),
            URLQueryItem(name: "month", value: String(month.month)),
        ]
        let path: String
        switch source {
        case .personal:
            path = "/users/\(login)/settings/billing/ai_credit/usage"
        case .organization(let org):
            guard !org.isEmpty,
                  org.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil
            else { throw GitHubAPIError.invalidOrganization }
            path = "/organizations/\(org)/settings/billing/ai_credit/usage"
            query.append(URLQueryItem(name: "user", value: login))
        }
        return try await get(path, token: token, query: query)
    }

    private func get<T: Decodable>(
        _ path: String,
        token: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        var url = URLComponents()
        url.scheme = "https"
        url.host = "api.github.com"
        url.path = path
        url.queryItems = query.isEmpty ? nil : query
        guard let endpoint = url.url else { throw GitHubAPIError.unexpectedResponse }

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CopilotAICMenu", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GitHubAPIError.unexpectedResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAPIError.http(response.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GitHubAPIError.unexpectedResponse
        }
    }
}

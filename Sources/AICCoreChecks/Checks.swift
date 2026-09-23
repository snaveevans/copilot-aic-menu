import Foundation
import AICCore

@main
struct CoreChecks {
    static func main() async throws {
        let json = """
        {"usageItems": [
          {"product":"Copilot AI Credits", "unitType":"ai-credits", "grossQuantity":12.5, "netQuantity":2},
          {"product":"Copilot AI Credits", "unitType":"ai-credits", "grossQuantity":0.25},
          {"product":"Other AI Credits", "unitType":"ai-credits", "grossQuantity":100},
          {"product":"Copilot", "unitType":"requests", "grossQuantity":200}
        ]}
        """
        let report = try JSONDecoder().decode(BillingReport.self, from: Data(json.utf8))
        check(report.copilotAICs == Decimal(string: "12.75")!, "gross Copilot credits only")
        let empty = try JSONDecoder().decode(BillingReport.self, from: Data(#"{"usageItems":[]}"#.utf8))
        check(empty.copilotAICs == nil, "empty report is unknown, not zero")
        let orgExample = try JSONDecoder().decode(BillingReport.self, from: Data(#"{"usageItems":[{"product":"Copilot","sku":"Copilot AI Credits","unitType":"credits","grossQuantity":51}]}"#.utf8))
        check(orgExample.copilotAICs == 51, "organization billing credit units")
        let measuredZero = try JSONDecoder().decode(BillingReport.self, from: Data(#"{"usageItems":[{"product":"Copilot AI Credits","unitType":"ai-credits","grossQuantity":0}]}"#.utf8))
        check(measuredZero.copilotAICs == 0, "explicit zero is zero")

        let date = ISO8601DateFormatter().date(from: "2026-01-01T00:15:00Z")!
        check(BillingMonth.current(at: date) == BillingMonth(year: 2026, month: 1), "UTC billing month")
        let snapshot = try JSONDecoder().decode(CopilotQuota.self, from: Data(#"{"login":"octocat","entitlement":40000,"remaining":30864,"credits_used":15059,"token_based_billing":true,"has_quota":true,"reset":"2026-10-01"}"#.utf8))
        check(snapshot.used == 9136, "quota used is entitlement minus remaining, not credits_used")
        check(snapshot.percentUsed == Decimal(string: "22.84")!, "percent of allowance used")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let client = GitHubClient(session: URLSession(configuration: config))
        StubProtocol.handler = { request in
            check(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token", "authorization")
            check(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10", "API version")
            if request.url?.path == "/user" {
                return Data(#"{"login":"octocat"}"#.utf8)
            }
            check(request.url?.path == "/users/octocat/settings/billing/ai_credit/usage", "billing endpoint")
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            check(parts?.queryItems?.first(where: { $0.name == "year" })?.value == "2026", "year query")
            check(parts?.queryItems?.first(where: { $0.name == "month" })?.value == "3", "month query")
            return Data(#"{"usageItems":[{"product":"Copilot AI Credits","unitType":"ai-credits","grossQuantity":42}]}"#.utf8)
        }
        defer { StubProtocol.handler = nil }
        let login = try await client.login(token: "test-token")
        let credits = try await client.credits(token: "test-token", login: login, month: BillingMonth(year: 2026, month: 3))
        check(credits.copilotAICs == 42, "personal API response")

        StubProtocol.handler = { request in
            check(request.url?.path == "/organizations/example-org/settings/billing/ai_credit/usage", "org billing endpoint")
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            check(parts?.queryItems?.first(where: { $0.name == "user" })?.value == "octocat", "org user filter")
            return Data(#"{"usageItems":[{"product":"Copilot","sku":"Copilot AI Credits","unitType":"credits","grossQuantity":51}]}"#.utf8)
        }
        let orgCredits = try await client.credits(token: "test-token", login: login, month: BillingMonth(year: 2026, month: 3), source: .organization("example-org"))
        check(orgCredits.copilotAICs == 51, "org API response")
        print("All AIC core checks passed.")
        if CommandLine.arguments.contains("--live") {
            let quota = try await CopilotQuotaClient().fetch()
            print("Current Copilot quota for @\(quota.login): \(quota.used!) / \(quota.entitlement) AIC; resets \(quota.reset ?? "unknown")")
        }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
        guard condition() else {
            fputs("Failed: \(description)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}

private final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Data)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let data = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

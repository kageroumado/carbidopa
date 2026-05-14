import Foundation

struct CopilotToken: Sendable {
    let token: String
    let expiresAt: Date
    let refreshIn: Int

    var isExpired: Bool {
        Date() >= expiresAt
    }
}

enum GitHubAPI {
    // MARK: - Exchange GitHub token for Copilot token

    static func exchangeForCopilotToken(githubToken: String) async throws -> CopilotToken {
        let url = URL(string: "https://api.github.com/copilot_internal/v2/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in CopilotHeaders.githubHeaders(token: githubToken) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw GitHubAPIError.tokenExchangeFailed(statusCode: statusCode, body: body)
        }

        struct TokenResponse: Decodable {
            let token: String
            let expires_at: Int
            let refresh_in: Int
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return CopilotToken(
            token: tokenResponse.token,
            expiresAt: Date(timeIntervalSince1970: Double(tokenResponse.expires_at)),
            refreshIn: tokenResponse.refresh_in,
        )
    }

    // MARK: - Usage

    static func getUsage(githubToken: String) async throws -> Data {
        let url = URL(string: "https://api.github.com/copilot_internal/v2/usage")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in CopilotHeaders.githubHeaders(token: githubToken) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    // MARK: - User Info (quota)

    static func getUserInfo(githubToken: String) async throws -> CopilotUserInfo {
        let url = URL(string: "https://api.github.com/copilot_internal/user")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in CopilotHeaders.githubHeaders(token: githubToken) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw GitHubAPIError.tokenExchangeFailed(statusCode: statusCode, body: body)
        }

        return try JSONDecoder().decode(CopilotUserInfo.self, from: data)
    }
}

// MARK: - User Info Types

struct CopilotUserInfo: Decodable {
    let quotaSnapshots: QuotaSnapshots?
    let quotaResetDate: String?

    enum CodingKeys: String, CodingKey {
        case quotaSnapshots = "quota_snapshots"
        case quotaResetDate = "quota_reset_date"
    }

    struct QuotaSnapshots: Decodable {
        let premiumInteractions: QuotaSnapshot?

        enum CodingKeys: String, CodingKey {
            case premiumInteractions = "premium_interactions"
        }
    }

    struct QuotaSnapshot: Decodable {
        let entitlement: Int
        let remaining: Int
        let unlimited: Bool

        enum CodingKeys: String, CodingKey {
            case entitlement, remaining, unlimited
        }
    }
}

enum GitHubAPIError: Error, CustomStringConvertible {
    case tokenExchangeFailed(statusCode: Int, body: String)

    var description: String {
        switch self {
        case let .tokenExchangeFailed(statusCode, body):
            "Token exchange failed (\(statusCode)): \(body)"
        }
    }
}

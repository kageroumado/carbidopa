import Foundation
import Hummingbird
import NIOCore

enum UsageRoute {
    static func handle(tokenManager: TokenManager) async throws -> Response {
        guard let githubToken = await tokenManager.currentGitHubToken else {
            return ProxyResponse.error(status: .unauthorized, message: "Not authenticated")
        }

        do {
            let data = try await GitHubAPI.getUsage(githubToken: githubToken)
            return ProxyResponse.json(data: data)
        } catch let error as GitHubAPIError {
            if case let .tokenExchangeFailed(statusCode, body) = error {
                return ProxyResponse.error(status: .init(code: statusCode), message: body)
            }
            throw error
        }
    }
}

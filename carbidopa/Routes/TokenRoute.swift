import Foundation
import Hummingbird
import NIOCore

enum TokenRoute {
    private struct TokenInfo: Encodable {
        let authenticated: Bool
        let status: String
    }

    static func handle(tokenManager: TokenManager) async throws -> Response {
        let copilotToken = await tokenManager.currentCopilotTokenString
        let status = await tokenManager.tokenStatus

        let statusString = switch status {
        case .notFound: "not_found"
        case .loading: "loading"
        case .valid: "valid"
        case .expired: "expired"
        case let .error(msg): "error: \(msg)"
        }

        let info = TokenInfo(
            authenticated: copilotToken != nil,
            status: statusString,
        )
        return ProxyResponse.json(body: info)
    }
}

import Foundation
import Hummingbird
import NIOCore

enum ModelsRoute {
    static func handle(tokenManager: TokenManager, copilotClient: CopilotClient) async throws -> Response {
        guard let token = await tokenManager.currentCopilotTokenString else {
            return ProxyResponse.error(status: .unauthorized, message: "Not authenticated with Copilot")
        }

        do {
            let data = try await copilotClient.models(token: token)
            return ProxyResponse.json(data: data)
        } catch let error as CopilotError {
            if case let .httpError(code, body) = error {
                return ProxyResponse.error(status: .init(code: code), message: body)
            }
            throw error
        }
    }
}

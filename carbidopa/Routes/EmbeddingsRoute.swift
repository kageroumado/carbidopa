import Foundation
import Hummingbird
import NIOCore

enum EmbeddingsRoute {
    static func handle(
        request: Request,
        context _: some RequestContext,
        tokenManager: TokenManager,
        copilotClient: CopilotClient,
    ) async throws -> Response {
        let prepared = try await RouteHelper.requireBodyAndToken(request, tokenManager: tokenManager)
        guard case let .success(bodyData, token) = prepared else {
            return prepared.errorResponse
        }

        do {
            let data = try await copilotClient.embeddings(payload: bodyData, token: token)
            return ProxyResponse.json(data: data)
        } catch let error as CopilotError {
            if case let .httpError(code, body) = error {
                return ProxyResponse.error(status: .init(code: code), message: body)
            }
            throw error
        }
    }
}

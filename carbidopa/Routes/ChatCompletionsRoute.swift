import Foundation
import Hummingbird
import NIOCore

enum ChatCompletionsRoute {
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

        guard let payload = try? JSONDecoder().decode(ChatCompletionsPayload.self, from: bodyData) else {
            do {
                let data = try await copilotClient.chatCompletions(payload: bodyData, token: token)
                return ProxyResponse.json(data: data)
            } catch let error as CopilotError {
                if case let .httpError(code, body) = error {
                    return ProxyResponse.error(status: .init(code: code), message: body)
                }
                throw error
            }
        }

        let hasVision = payload.messages.contains { $0.content?.containsImageURL ?? false }

        do {
            if payload.stream ?? false {
                let bytes = try await copilotClient.chatCompletionsStream(
                    payload: bodyData, token: token, isVision: hasVision,
                )
                return ProxyResponse.sse(from: bytes)
            } else {
                let data = try await copilotClient.chatCompletions(
                    payload: bodyData, token: token, isVision: hasVision,
                )
                return ProxyResponse.json(data: data)
            }
        } catch let error as CopilotError {
            if case let .httpError(code, body) = error {
                return ProxyResponse.error(status: .init(code: code), message: body)
            }
            throw error
        }
    }
}

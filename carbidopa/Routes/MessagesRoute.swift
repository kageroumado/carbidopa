import Foundation
import Hummingbird
import NIOCore

enum MessagesRoute {
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

        let anthropicPayload: AnthropicMessagesPayload
        do {
            anthropicPayload = try JSONDecoder().decode(AnthropicMessagesPayload.self, from: bodyData)
        } catch {
            return ProxyResponse.error(status: .badRequest, message: "Invalid request: \(error.localizedDescription)")
        }

        let isStreaming = anthropicPayload.stream ?? false
        let isVision = PayloadTranslation.detectVision(anthropicPayload)

        var openAIPayload = PayloadTranslation.translate(anthropicPayload)
        openAIPayload.stream = isStreaming
        openAIPayload.streamOptions = isStreaming ? .init(includeUsage: true) : nil
        let openAIBody = try JSONEncoder().encode(openAIPayload)

        do {
            if isStreaming {
                let bytes = try await copilotClient.chatCompletionsStream(
                    payload: openAIBody, token: token, isVision: isVision,
                )
                let translator = StreamTranslator(requestModel: anthropicPayload.model)
                return ProxyResponse.sse(from: bytes) { line in
                    translator.processLine(line).map(\.sseString)
                }
            } else {
                let data = try await copilotClient.chatCompletions(
                    payload: openAIBody, token: token, isVision: isVision,
                )
                let openAIResponse = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
                let anthropicResponse = ResponseTranslation.translate(openAIResponse, requestModel: anthropicPayload.model)
                let responseData = try JSONEncoder().encode(anthropicResponse)
                return ProxyResponse.json(data: responseData)
            }
        } catch let error as CopilotError {
            if case let .httpError(code, body) = error {
                return ProxyResponse.error(status: .init(code: code), message: body)
            }
            throw error
        }
    }
}

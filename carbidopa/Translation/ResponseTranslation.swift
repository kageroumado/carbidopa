import Foundation

enum ResponseTranslation {
    static func translate(_ response: ChatCompletionsResponse, requestModel: String) -> AnthropicMessagesResponse {
        let choice = response.choices.first

        var content: [AnthropicContent] = []

        // Text content
        if let text = choice?.message.content, !text.isEmpty {
            content.append(.text(text))
        }

        // Tool calls
        if let toolCalls = choice?.message.toolCalls {
            for tc in toolCalls {
                let input = parseJSON(tc.function.arguments)
                content.append(.toolUse(id: tc.id, name: tc.function.name, input: input))
            }
        }

        // Map finish reason
        let stopReason = mapFinishReason(choice?.finishReason)

        // Map usage
        let cachedTokens = response.usage?.promptTokensDetails?.cachedTokens ?? 0
        let promptTokens = response.usage?.promptTokens ?? 0
        let inputTokens = promptTokens - cachedTokens

        let usage = AnthropicUsage(
            inputTokens: max(inputTokens, 0),
            outputTokens: response.usage?.completionTokens ?? 0,
            cacheCreationInputTokens: nil,
            cacheReadInputTokens: cachedTokens > 0 ? cachedTokens : nil,
        )

        return AnthropicMessagesResponse(
            id: response.id,
            type: "message",
            role: "assistant",
            content: content,
            model: requestModel,
            stopReason: stopReason,
            usage: usage,
        )
    }

    static func mapFinishReason(_ reason: String?) -> String? {
        switch reason {
        case "stop": "end_turn"
        case "length": "max_tokens"
        case "tool_calls": "tool_use"
        case nil: nil
        default: reason
        }
    }

    private static func parseJSON(_ string: String) -> JSONValue {
        guard let data = string.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .object([:])
        }
        return value
    }
}

import Foundation
import Hummingbird
import NIOCore

enum TokenCountRoute {
    static func handle(
        request: Request,
        context _: some RequestContext,
        tokenManager _: TokenManager,
    ) async throws -> Response {
        var request = request
        let body = try await request.collectBody(upTo: 4 * 1_024 * 1_024)
        let bodyData = Data(body.readableBytesView)

        guard !bodyData.isEmpty else {
            return ProxyResponse.error(status: .badRequest, message: "Missing request body")
        }

        let payload: AnthropicMessagesPayload
        do {
            payload = try JSONDecoder().decode(AnthropicMessagesPayload.self, from: bodyData)
        } catch {
            return ProxyResponse.error(status: .badRequest, message: "Invalid request: \(error.localizedDescription)")
        }

        let tokenCount = estimateTokenCount(payload)
        return ProxyResponse.json(body: AnthropicTokenCountResponse(inputTokens: tokenCount))
    }

    // MARK: - Token Estimation

    private static func estimateTokenCount(_ payload: AnthropicMessagesPayload) -> Int {
        var count = 0

        if let system = payload.system {
            count += estimateTokens(system.textValue) + 4
        }

        for message in payload.messages {
            count += 4
            for block in message.content.blocks {
                switch block {
                case let .text(text):
                    count += estimateTokens(text)
                case .image:
                    count += 1_000
                case let .toolUse(_, name, input):
                    count += estimateTokens(name)
                    if let data = try? JSONEncoder().encode(input),
                       let str = String(data: data, encoding: .utf8) {
                        count += estimateTokens(str)
                    }
                case let .toolResult(_, content, _):
                    count += estimateTokens(content?.textValue ?? "")
                }
            }
        }

        if let tools = payload.tools {
            for tool in tools {
                count += estimateTokens(tool.name)
                count += estimateTokens(tool.description ?? "")
                if let schema = tool.inputSchema,
                   let data = try? JSONEncoder().encode(schema),
                   let str = String(data: data, encoding: .utf8) {
                    count += estimateTokens(str)
                }
            }
        }

        let model = payload.model.lowercased()
        if model.contains("claude") {
            count = Int(Double(count) * 1.15)
        } else if model.contains("grok") {
            count = Int(Double(count) * 1.03)
        }

        return max(count, 1)
    }

    private static func estimateTokens(_ text: String) -> Int {
        max(text.count / 4, 1)
    }
}

import Foundation
import Synchronization

final class StreamTranslator: Sendable {
    let requestModel: String
    private let state = Mutex(State())

    init(requestModel: String) {
        self.requestModel = requestModel
    }

    func processLine(_ line: String) -> [SSEOutput] {
        guard line.hasPrefix("data: ") else { return [] }
        let data = String(line.dropFirst(6))

        if data == "[DONE]" {
            return state.withLock { state in
                StreamTranslator.finalize(&state)
            }
        }

        guard let jsonData = data.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: jsonData) else {
            return []
        }

        return state.withLock { state in
            StreamTranslator.processChunk(chunk, state: &state, requestModel: requestModel)
        }
    }
}

// MARK: - State

extension StreamTranslator {
    private struct State {
        var messageStartSent = false
        var messageId = ""
        var model = ""
        var contentBlockIndex = 0
        var textBlockOpen = false
        var toolBlockOpen = false
        var toolCallAccumulators: [Int: ToolCallAccumulator] = [:]
        var finishReason: String?
        var finalUsage: OpenAIUsage?
    }
}

// MARK: - Processing (operates on inout State)

extension StreamTranslator {
    private static func processChunk(_ chunk: OpenAIStreamChunk, state: inout State, requestModel: String) -> [SSEOutput] {
        var events: [SSEOutput] = []

        if !state.messageStartSent {
            state.messageStartSent = true
            state.messageId = chunk.id ?? "msg_\(UUID().uuidString)"
            state.model = chunk.model ?? requestModel

            let json = """
            {"type":"message_start","message":{"id":"\(state.messageId)","type":"message","role":"assistant","content":[],"model":"\(state.model)","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":0,"output_tokens":0}}}
            """
            events.append(SSEOutput(event: "message_start", data: json))
        }

        guard let choice = chunk.choices?.first else {
            if let usage = chunk.usage {
                state.finalUsage = usage
            }
            return events
        }

        let delta = choice.delta

        // Text content
        if let text = delta?.content, !text.isEmpty {
            if !state.textBlockOpen {
                state.textBlockOpen = true
                let json = """
                {"type":"content_block_start","index":\(state.contentBlockIndex),"content_block":{"type":"text","text":""}}
                """
                events.append(SSEOutput(event: "content_block_start", data: json))
            }

            let escapedText = escapeJSON(text)
            let json = """
            {"type":"content_block_delta","index":\(state.contentBlockIndex),"delta":{"type":"text_delta","text":"\(escapedText)"}}
            """
            events.append(SSEOutput(event: "content_block_delta", data: json))
        }

        // Tool calls
        if let toolCalls = delta?.toolCalls {
            for tc in toolCalls {
                let tcIndex = tc.index ?? 0

                if let id = tc.id, let name = tc.function?.name {
                    if state.textBlockOpen {
                        state.textBlockOpen = false
                        events.append(SSEOutput(
                            event: "content_block_stop",
                            data: "{\"type\":\"content_block_stop\",\"index\":\(state.contentBlockIndex)}",
                        ))
                        state.contentBlockIndex += 1
                    }

                    if state.toolBlockOpen {
                        events.append(SSEOutput(
                            event: "content_block_stop",
                            data: "{\"type\":\"content_block_stop\",\"index\":\(state.contentBlockIndex)}",
                        ))
                        state.contentBlockIndex += 1
                    }

                    state.toolBlockOpen = true
                    state.toolCallAccumulators[tcIndex] = ToolCallAccumulator(id: id, name: name)

                    let escapedName = escapeJSON(name)
                    let json = """
                    {"type":"content_block_start","index":\(state.contentBlockIndex),"content_block":{"type":"tool_use","id":"\(id)","name":"\(escapedName)","input":{}}}
                    """
                    events.append(SSEOutput(event: "content_block_start", data: json))
                }

                if let args = tc.function?.arguments, !args.isEmpty {
                    state.toolCallAccumulators[tcIndex]?.arguments += args

                    let escapedArgs = escapeJSON(args)
                    let json = """
                    {"type":"content_block_delta","index":\(state.contentBlockIndex),"delta":{"type":"input_json_delta","partial_json":"\(escapedArgs)"}}
                    """
                    events.append(SSEOutput(event: "content_block_delta", data: json))
                }
            }
        }

        if let fr = choice.finishReason {
            state.finishReason = fr
        }

        if let usage = chunk.usage {
            state.finalUsage = usage
        }

        return events
    }

    private static func finalize(_ state: inout State) -> [SSEOutput] {
        var events: [SSEOutput] = []

        if state.textBlockOpen {
            events.append(SSEOutput(
                event: "content_block_stop",
                data: "{\"type\":\"content_block_stop\",\"index\":\(state.contentBlockIndex)}",
            ))
            state.contentBlockIndex += 1
        }

        if state.toolBlockOpen {
            events.append(SSEOutput(
                event: "content_block_stop",
                data: "{\"type\":\"content_block_stop\",\"index\":\(state.contentBlockIndex)}",
            ))
            state.contentBlockIndex += 1
        }

        let stopReason = ResponseTranslation.mapFinishReason(state.finishReason) ?? "end_turn"
        let cachedTokens = state.finalUsage?.promptTokensDetails?.cachedTokens ?? 0
        let promptTokens = state.finalUsage?.promptTokens ?? 0
        let inputTokens = max(promptTokens - cachedTokens, 0)
        let outputTokens = state.finalUsage?.completionTokens ?? 0

        let deltaJSON = """
        {"type":"message_delta","delta":{"stop_reason":"\(stopReason)","stop_sequence":null},"usage":{"input_tokens":\(inputTokens),"output_tokens":\(outputTokens),"cache_read_input_tokens":\(cachedTokens)}}
        """
        events.append(SSEOutput(event: "message_delta", data: deltaJSON))
        events.append(SSEOutput(event: "message_stop", data: "{\"type\":\"message_stop\"}"))

        return events
    }
}

// MARK: - Helpers

private struct ToolCallAccumulator {
    var id: String
    var name: String
    var arguments: String = ""
}

private func escapeJSON(_ string: String) -> String {
    var result = ""
    result.reserveCapacity(string.count)
    for scalar in string.unicodeScalars {
        switch scalar {
        case "\\": result += "\\\\"
        case "\"": result += "\\\""
        case "\n": result += "\\n"
        case "\r": result += "\\r"
        case "\t": result += "\\t"
        case "\u{08}": result += "\\b"
        case "\u{0C}": result += "\\f"
        default:
            if scalar.value < 0x20 {
                result += String(format: "\\u%04x", scalar.value)
            } else {
                result += String(scalar)
            }
        }
    }
    return result
}

// MARK: - SSE Output

struct SSEOutput: Sendable {
    let event: String
    let data: String

    var sseString: String {
        "event: \(event)\ndata: \(data)\n\n"
    }
}

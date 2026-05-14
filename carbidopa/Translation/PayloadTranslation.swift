import Foundation

enum PayloadTranslation {
    static func translate(_ payload: AnthropicMessagesPayload) -> ChatCompletionsPayload {
        var messages: [OpenAIMessage] = []

        if let system = payload.system {
            messages.append(OpenAIMessage(role: "system", content: .text(system.textValue)))
        }

        for message in payload.messages {
            let blocks = message.content.blocks

            if message.role == "user" {
                var userParts: [OpenAIContentPart] = []

                for block in blocks {
                    switch block {
                    case let .text(text):
                        userParts.append(.text(text))

                    case let .image(source):
                        let dataURI = "data:\(source.mediaType);base64,\(source.data)"
                        userParts.append(.imageURL(url: dataURI, detail: nil))

                    case let .toolResult(toolUseId, content, _):
                        if !userParts.isEmpty {
                            messages.append(OpenAIMessage(role: "user", content: .parts(userParts)))
                            userParts = []
                        }
                        messages.append(OpenAIMessage(
                            role: "tool",
                            content: .text(content?.textValue ?? ""),
                            toolCallId: toolUseId,
                        ))

                    case .toolUse:
                        break
                    }
                }

                if !userParts.isEmpty {
                    if userParts.count == 1, case let .text(t) = userParts[0] {
                        messages.append(OpenAIMessage(role: "user", content: .text(t)))
                    } else {
                        messages.append(OpenAIMessage(role: "user", content: .parts(userParts)))
                    }
                }

            } else if message.role == "assistant" {
                var textContent: String?
                var toolCalls: [OpenAIToolCall] = []
                let encoder = JSONEncoder()

                for block in blocks {
                    switch block {
                    case let .text(text):
                        textContent = (textContent ?? "") + text

                    case let .toolUse(id, name, input):
                        let argsString = (try? encoder.encode(input))
                            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                        toolCalls.append(OpenAIToolCall(
                            id: id,
                            function: OpenAIFunctionCall(name: name, arguments: argsString),
                        ))

                    default:
                        break
                    }
                }

                var msg = OpenAIMessage(
                    role: "assistant",
                    content: textContent.map { .text($0) },
                )
                if !toolCalls.isEmpty {
                    msg.toolCalls = toolCalls
                }
                messages.append(msg)
            }
        }

        let tools = payload.tools?.map { tool in
            OpenAITool(function: OpenAIFunctionDef(
                name: tool.name,
                description: tool.description,
                parameters: tool.inputSchema,
            ))
        }

        let toolChoice: OpenAIToolChoice? = payload.toolChoice.flatMap { choice in
            switch choice {
            case .auto: .auto
            case .any: .required
            case let .tool(name): .function(name: name)
            }
        }

        let stop: StopSequence? = payload.stopSequences.flatMap { seqs in
            seqs.count == 1 ? .single(seqs[0]) : .multiple(seqs)
        }

        return ChatCompletionsPayload(
            model: normalizeModelName(payload.model),
            messages: messages,
            stream: payload.stream,
            maxTokens: payload.maxTokens,
            temperature: payload.temperature,
            topP: payload.topP,
            stop: stop,
            tools: tools,
            toolChoice: toolChoice,
        )
    }

    static func normalizeModelName(_ model: String) -> String {
        var name = model

        // Strip date suffixes like claude-sonnet-4-20250514 → claude-sonnet-4
        let dateSuffix = #"-\d{8}$"#
        if let range = name.range(of: dateSuffix, options: .regularExpression) {
            name = String(name[..<range.lowerBound])
        }

        // Fix version separators: claude-sonnet-4-5 → claude-sonnet-4.5
        // Matches a base model name ending in a digit, followed by -digit(s) version
        let versionFix = #"(\d)-(\d+(?:\.\d+)*)$"#
        if let range = name.range(of: versionFix, options: .regularExpression) {
            let matched = String(name[range])
            let fixed = matched.replacingOccurrences(of: "-", with: ".")
            name = name[..<range.lowerBound] + fixed
        }

        return name
    }

    static func detectVision(_ payload: AnthropicMessagesPayload) -> Bool {
        payload.messages.contains { message in
            message.content.blocks.contains { if case .image = $0 { true } else { false } }
        }
    }
}

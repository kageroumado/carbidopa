import Foundation

// MARK: - Messages Request

struct AnthropicMessagesPayload: Codable, Sendable {
    var model: String
    var maxTokens: Int
    var messages: [AnthropicMessage]
    var system: AnthropicSystem?
    var stream: Bool?
    var tools: [AnthropicTool]?
    var toolChoice: AnthropicToolChoice?
    var metadata: AnthropicMetadata?
    var stopSequences: [String]?
    var temperature: Double?
    var topP: Double?
    var topK: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case system
        case stream
        case tools
        case metadata
        case temperature
        case maxTokens = "max_tokens"
        case toolChoice = "tool_choice"
        case stopSequences = "stop_sequences"
        case topP = "top_p"
        case topK = "top_k"
    }
}

struct AnthropicMetadata: Codable, Sendable {
    var userId: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

// MARK: - System Prompt

enum AnthropicSystem: Codable, Sendable {
    case text(String)
    case blocks([AnthropicSystemBlock])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .text(s)
        } else {
            self = try .blocks(container.decode([AnthropicSystemBlock].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(s): try container.encode(s)
        case let .blocks(b): try container.encode(b)
        }
    }

    var textValue: String {
        switch self {
        case let .text(s): s
        case let .blocks(blocks):
            blocks.compactMap { block in
                if case let .text(t) = block { return t }
                return nil
            }.joined(separator: "\n\n")
        }
    }
}

enum AnthropicSystemBlock: Codable, Sendable {
    case text(String)

    enum CodingKeys: String, CodingKey {
        case type
        case text
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown system block type: \(type)")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }
}

// MARK: - Messages

struct AnthropicMessage: Codable, Sendable {
    var role: String
    var content: AnthropicMessageContent

    enum CodingKeys: String, CodingKey {
        case role
        case content
    }
}

enum AnthropicMessageContent: Codable, Sendable {
    case text(String)
    case blocks([AnthropicContent])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .text(s)
        } else {
            self = try .blocks(container.decode([AnthropicContent].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(s): try container.encode(s)
        case let .blocks(b): try container.encode(b)
        }
    }

    var blocks: [AnthropicContent] {
        switch self {
        case let .text(s): [.text(s)]
        case let .blocks(b): b
        }
    }
}

// MARK: - Content Blocks

enum AnthropicContent: Codable, Sendable {
    case text(String)
    case image(source: AnthropicImageSource)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseId: String, content: AnthropicToolResultContent?, isError: Bool?)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case id
        case name
        case input
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image":
            let source = try container.decode(AnthropicImageSource.self, forKey: .source)
            self = .image(source: source)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode(JSONValue.self, forKey: .input)
            self = .toolUse(id: id, name: name, input: input)
        case "tool_result":
            let toolUseId = try container.decode(String.self, forKey: .toolUseId)
            let content = try container.decodeIfPresent(AnthropicToolResultContent.self, forKey: .content)
            let isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
            self = .toolResult(toolUseId: toolUseId, content: content, isError: isError)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content type: \(type)")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(source):
            try container.encode("image", forKey: .type)
            try container.encode(source, forKey: .source)
        case let .toolUse(id, name, input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case let .toolResult(toolUseId, content, isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encodeIfPresent(content, forKey: .content)
            try container.encodeIfPresent(isError, forKey: .isError)
        }
    }
}

enum AnthropicToolResultContent: Codable, Sendable {
    case text(String)
    case blocks([AnthropicContent])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .text(s)
        } else {
            self = try .blocks(container.decode([AnthropicContent].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(s): try container.encode(s)
        case let .blocks(b): try container.encode(b)
        }
    }

    var textValue: String {
        switch self {
        case let .text(s): s
        case let .blocks(blocks):
            blocks.compactMap { block in
                if case let .text(t) = block { return t }
                return nil
            }.joined(separator: "\n")
        }
    }
}

// MARK: - Image Source

struct AnthropicImageSource: Codable, Sendable {
    var type: String
    var mediaType: String
    var data: String

    enum CodingKeys: String, CodingKey {
        case type
        case data
        case mediaType = "media_type"
    }
}

// MARK: - Tools

struct AnthropicTool: Codable, Sendable {
    var name: String
    var description: String?
    var inputSchema: JSONValue?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

// MARK: - Tool Choice

enum AnthropicToolChoice: Codable, Sendable {
    case auto
    case any
    case tool(name: String)

    struct ToolChoiceValue: Codable, Sendable {
        var type: String
        var name: String?
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(ToolChoiceValue.self)
        switch value.type {
        case "auto": self = .auto
        case "any": self = .any
        case "tool":
            guard let name = value.name else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Tool choice 'tool' requires name")
            }
            self = .tool(name: name)
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown tool_choice type: \(value.type)")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto: try container.encode(ToolChoiceValue(type: "auto"))
        case .any: try container.encode(ToolChoiceValue(type: "any"))
        case let .tool(name): try container.encode(ToolChoiceValue(type: "tool", name: name))
        }
    }
}

// MARK: - Messages Response

struct AnthropicMessagesResponse: Codable, Sendable {
    var id: String
    var type: String
    var role: String
    var content: [AnthropicContent]
    var model: String
    var stopReason: String?
    var stopSequence: String?
    var usage: AnthropicUsage

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case role
        case content
        case model
        case usage
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
    }
}

struct AnthropicUsage: Codable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationInputTokens: Int?
    var cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

// MARK: - Streaming Events

enum AnthropicStreamEventType: String, Codable, Sendable {
    case messageStart = "message_start"
    case contentBlockStart = "content_block_start"
    case contentBlockDelta = "content_block_delta"
    case contentBlockStop = "content_block_stop"
    case messageDelta = "message_delta"
    case messageStop = "message_stop"
    case ping
    case error
}

struct AnthropicStreamEvent: Codable, Sendable {
    var type: AnthropicStreamEventType
}

// MARK: - Token Count

struct AnthropicTokenCountResponse: Codable, Sendable {
    var inputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
    }
}

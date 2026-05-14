import Foundation

// MARK: - Chat Completions Request

struct ChatCompletionsPayload: Codable, Sendable {
    var model: String
    var messages: [OpenAIMessage]
    var stream: Bool?
    var maxTokens: Int?
    var temperature: Double?
    var topP: Double?
    var n: Int?
    var stop: StopSequence?
    var presencePenalty: Double?
    var frequencyPenalty: Double?
    var tools: [OpenAITool]?
    var toolChoice: OpenAIToolChoice?
    var streamOptions: StreamOptions?

    struct StreamOptions: Codable, Sendable {
        var includeUsage: Bool

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case n
        case stop
        case tools
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case toolChoice = "tool_choice"
        case streamOptions = "stream_options"
    }
}

enum StopSequence: Codable, Sendable {
    case single(String)
    case multiple([String])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .single(s)
        } else {
            self = try .multiple(container.decode([String].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .single(s): try container.encode(s)
        case let .multiple(a): try container.encode(a)
        }
    }
}

// MARK: - Messages

struct OpenAIMessage: Codable, Sendable {
    var role: String
    var content: OpenAIMessageContent?
    var toolCalls: [OpenAIToolCall]?
    var toolCallId: String?
    var name: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case name
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }
}

enum OpenAIMessageContent: Codable, Sendable {
    case text(String)
    case parts([OpenAIContentPart])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .text(s)
        } else {
            self = try .parts(container.decode([OpenAIContentPart].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(s): try container.encode(s)
        case let .parts(p): try container.encode(p)
        }
    }

    var textValue: String? {
        switch self {
        case let .text(s): return s
        case let .parts(parts):
            let texts = parts.compactMap { part -> String? in
                if case let .text(t) = part { return t }
                return nil
            }
            return texts.isEmpty ? nil : texts.joined()
        }
    }

    var containsImageURL: Bool {
        switch self {
        case .text: false
        case let .parts(parts):
            parts.contains { part in
                if case .imageURL = part { return true }
                return false
            }
        }
    }
}

enum OpenAIContentPart: Codable, Sendable {
    case text(String)
    case imageURL(url: String, detail: String?)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    struct ImageURLValue: Codable, Sendable {
        var url: String
        var detail: String?
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image_url":
            let img = try container.decode(ImageURLValue.self, forKey: .imageURL)
            self = .imageURL(url: img.url, detail: img.detail)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content part type: \(type)")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .imageURL(url, detail):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURLValue(url: url, detail: detail), forKey: .imageURL)
        }
    }
}

// MARK: - Tool Calls

struct OpenAIToolCall: Codable, Sendable {
    var id: String
    var type: String
    var function: OpenAIFunctionCall

    init(id: String, type: String = "function", function: OpenAIFunctionCall) {
        self.id = id
        self.type = type
        self.function = function
    }
}

struct OpenAIFunctionCall: Codable, Sendable {
    var name: String
    var arguments: String
}

// MARK: - Tools

struct OpenAITool: Codable, Sendable {
    var type: String
    var function: OpenAIFunctionDef

    init(type: String = "function", function: OpenAIFunctionDef) {
        self.type = type
        self.function = function
    }
}

struct OpenAIFunctionDef: Codable, Sendable {
    var name: String
    var description: String?
    var parameters: JSONValue?
}

// MARK: - Tool Choice

enum OpenAIToolChoice: Codable, Sendable {
    case none
    case auto
    case required
    case function(name: String)

    struct FunctionChoice: Codable, Sendable {
        var type: String
        var function: FunctionName

        struct FunctionName: Codable, Sendable {
            var name: String
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            switch s {
            case "none": self = .none
            case "auto": self = .auto
            case "required": self = .required
            default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown tool_choice: \(s)")
            }
        } else {
            let fc = try container.decode(FunctionChoice.self)
            self = .function(name: fc.function.name)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .none: try container.encode("none")
        case .auto: try container.encode("auto")
        case .required: try container.encode("required")
        case let .function(name):
            try container.encode(FunctionChoice(type: "function", function: .init(name: name)))
        }
    }
}

// MARK: - Chat Completions Response

struct ChatCompletionsResponse: Codable, Sendable {
    var id: String
    var object: String
    var created: Int
    var model: String
    var choices: [OpenAIChoice]
    var usage: OpenAIUsage?
    var systemFingerprint: String?

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case model
        case choices
        case usage
        case systemFingerprint = "system_fingerprint"
    }
}

struct OpenAIChoice: Codable, Sendable {
    var index: Int
    var message: OpenAIResponseMessage
    var finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

struct OpenAIResponseMessage: Codable, Sendable {
    var role: String?
    var content: String?
    var toolCalls: [OpenAIToolCall]?
    var refusal: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case refusal
        case toolCalls = "tool_calls"
    }
}

struct OpenAIUsage: Codable, Sendable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    var promptTokensDetails: PromptTokensDetails?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case promptTokensDetails = "prompt_tokens_details"
    }

    struct PromptTokensDetails: Codable, Sendable {
        var cachedTokens: Int?

        enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }
}

// MARK: - Streaming

struct OpenAIStreamChunk: Codable, Sendable {
    var id: String?
    var object: String?
    var created: Int?
    var model: String?
    var choices: [OpenAIStreamChoice]?
    var usage: OpenAIUsage?
}

struct OpenAIStreamChoice: Codable, Sendable {
    var index: Int?
    var delta: OpenAIStreamDelta?
    var finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case delta
        case finishReason = "finish_reason"
    }
}

struct OpenAIStreamDelta: Codable, Sendable {
    var role: String?
    var content: String?
    var toolCalls: [OpenAIStreamToolCall]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
    }
}

struct OpenAIStreamToolCall: Codable, Sendable {
    var index: Int?
    var id: String?
    var type: String?
    var function: OpenAIStreamFunction?
}

struct OpenAIStreamFunction: Codable, Sendable {
    var name: String?
    var arguments: String?
}

// MARK: - Models

struct ModelsResponse: Codable, Sendable {
    var object: String?
    var data: [ModelObject]?
}

struct ModelObject: Codable, Sendable {
    var id: String
    var object: String?
    var created: Int?
    var ownedBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case ownedBy = "owned_by"
    }
}

// MARK: - Embeddings

struct EmbeddingsPayload: Codable, Sendable {
    var model: String
    var input: EmbeddingsInput

    enum EmbeddingsInput: Codable, Sendable {
        case single(String)
        case multiple([String])

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) {
                self = .single(s)
            } else {
                self = try .multiple(container.decode([String].self))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .single(s): try container.encode(s)
            case let .multiple(a): try container.encode(a)
            }
        }
    }
}

// MARK: - Generic JSON Value

enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = try .object(container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(b): try container.encode(b)
        case let .int(i): try container.encode(i)
        case let .double(d): try container.encode(d)
        case let .string(s): try container.encode(s)
        case let .array(a): try container.encode(a)
        case let .object(o): try container.encode(o)
        }
    }
}

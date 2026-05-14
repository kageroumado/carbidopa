import Foundation

actor CopilotClient {
    private let session: URLSession
    private let baseURL = "https://api.githubcopilot.com"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Chat Completions

    func chatCompletions(payload: Data, token: String, isVision: Bool = false) async throws -> Data {
        let request = buildRequest(path: "/chat/completions", method: "POST", token: token, body: payload, isVision: isVision)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    func chatCompletionsStream(payload: Data, token: String, isVision: Bool = false) async throws -> URLSession.AsyncBytes {
        var request = buildRequest(path: "/chat/completions", method: "POST", token: token, body: payload, isVision: isVision)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode) {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let body = String(data: errorData, encoding: .utf8) ?? "No body"
            throw CopilotError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
        return bytes
    }

    // MARK: - Embeddings

    func embeddings(payload: Data, token: String) async throws -> Data {
        let request = buildRequest(path: "/embeddings", method: "POST", token: token, body: payload)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    // MARK: - Models

    func models(token: String) async throws -> Data {
        let request = buildRequest(path: "/models", method: "GET", token: token)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    // MARK: - Private

    private func buildRequest(
        path: String,
        method: String,
        token: String,
        body: Data? = nil,
        isVision: Bool = false,
    ) -> URLRequest {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in CopilotHeaders.buildHeaders(token: token, isVision: isVision) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    private func validateResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CopilotError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No body"
            throw CopilotError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
    }
}

enum CopilotError: Error, CustomStringConvertible {
    case invalidResponse
    case httpError(statusCode: Int, body: String)

    var description: String {
        switch self {
        case .invalidResponse:
            "Invalid response from Copilot API"
        case let .httpError(statusCode, body):
            "Copilot API error \(statusCode): \(body)"
        }
    }
}

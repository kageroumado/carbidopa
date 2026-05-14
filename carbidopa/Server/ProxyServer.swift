import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import os

actor ProxyServer {
    private let logger = Logger.app(category: "ProxyServer")
    private let port: Int
    private let logStore: LogStore
    private let tokenManager: TokenManager
    private let copilotClient: CopilotClient
    private let rateLimiter: RateLimiter
    private var serverTask: Task<Void, any Error>?

    private(set) var isRunning = false

    init(
        port: Int = 4_141,
        logStore: LogStore,
        tokenManager: TokenManager,
        copilotClient: CopilotClient,
        rateLimiter: RateLimiter,
    ) {
        self.port = port
        self.logStore = logStore
        self.tokenManager = tokenManager
        self.copilotClient = copilotClient
        self.rateLimiter = rateLimiter
    }

    func start() async throws {
        guard !isRunning else { return }

        let router = buildRouter()
        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port)),
        )

        let task = Task.detached {
            try await app.run()
        }
        serverTask = task

        // Poll health check to confirm the server is actually listening.
        // If the server crashes (e.g., port in use), health checks will fail with connection refused.
        let healthURL = URL(string: "http://127.0.0.1:\(port)/")!
        var lastError: (any Error)?

        for attempt in 1 ... 5 {
            try await Task.sleep(for: .milliseconds(200))

            do {
                let (_, response) = try await URLSession.shared.data(from: healthURL)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    isRunning = true
                    logger.info("Proxy server started on port \(self.port) (health check passed on attempt \(attempt))")
                    return
                }
            } catch {
                lastError = error
            }
        }

        // All retries failed — server never started or crashed
        task.cancel()
        serverTask = nil
        throw ServerStartupError.healthCheckFailed(lastError)
    }

    func stop() {
        serverTask?.cancel()
        serverTask = nil
        isRunning = false
        logger.info("Proxy server stopped")
    }

    // MARK: - Router

    private func buildRouter() -> Router<BasicRequestContext> {
        let router = Router()

        router.add(middleware: CORSMiddleware(
            allowOrigin: .all,
            allowHeaders: [.contentType, .authorization, HTTPField.Name("x-api-key")!, HTTPField.Name("anthropic-version")!],
            allowMethods: [.get, .post, .put, .delete, .options],
        ))

        let logStore = logStore
        router.add(middleware: LoggingMiddleware(logStore: logStore))
        router.add(middleware: RateLimitMiddleware(limiter: rateLimiter))

        router.get("/") { _, _ in
            ProxyResponse.json(data: Data(#"{"status":"ok","message":"carbidopa is running"}"#.utf8))
        }

        let tm = tokenManager
        let cc = copilotClient

        router.post("/v1/chat/completions") { request, context in
            try await ChatCompletionsRoute.handle(request: request, context: context, tokenManager: tm, copilotClient: cc)
        }

        router.post("/v1/messages") { request, context in
            try await MessagesRoute.handle(request: request, context: context, tokenManager: tm, copilotClient: cc)
        }

        router.get("/v1/models") { _, _ in
            try await ModelsRoute.handle(tokenManager: tm, copilotClient: cc)
        }

        router.post("/v1/embeddings") { request, context in
            try await EmbeddingsRoute.handle(request: request, context: context, tokenManager: tm, copilotClient: cc)
        }

        router.post("/v1/messages/count_tokens") { request, context in
            try await TokenCountRoute.handle(request: request, context: context, tokenManager: tm)
        }

        router.get("/usage") { _, _ in
            try await UsageRoute.handle(tokenManager: tm)
        }

        router.get("/token") { _, _ in
            try await TokenRoute.handle(tokenManager: tm)
        }

        return router
    }
}

// MARK: - Errors

enum ServerStartupError: Error, LocalizedError {
    case healthCheckFailed((any Error)?)

    var errorDescription: String? {
        switch self {
        case let .healthCheckFailed(underlying):
            if let underlying {
                return "Server failed to start: health check failed after 5 attempts (\(underlying.localizedDescription))"
            }
            return "Server failed to start: health check failed after 5 attempts"
        }
    }
}

// MARK: - Logging Middleware

struct LoggingMiddleware<Context: RequestContext>: RouterMiddleware {
    let logStore: LogStore
    private let logger = Logger.app(category: "Router")

    func handle(
        _ request: HummingbirdCore.Request,
        context: Context,
        next: @concurrent (Request, Context) async throws -> Response,
    ) async throws -> Response {
        let start = ContinuousClock.now
        let method = request.method.rawValue
        let path = request.uri.path

        logger.info("-> \(method) \(path)")

        do {
            let response = try await next(request, context)
            let statusCode = Int(response.status.code)
            let ms = millisecondsSince(start)

            let level: OSLogType = statusCode >= 400 ? .error : .info
            logger.log(level: level, "<- \(method) \(path) \(statusCode) (\(ms)ms)")

            await logStore.append(RequestLog(
                timestamp: Date(), method: method, path: path,
                statusCode: statusCode, durationMs: ms, error: nil,
            ))
            return response
        } catch {
            let ms = millisecondsSince(start)
            logger.error("<- \(method) \(path) error: \(error)")

            await logStore.append(RequestLog(
                timestamp: Date(), method: method, path: path,
                statusCode: 500, durationMs: ms, error: error.localizedDescription,
            ))
            throw error
        }
    }

    private func millisecondsSince(_ start: ContinuousClock.Instant) -> Int {
        let elapsed = start.duration(to: .now)
        return Int(elapsed.components.seconds * 1_000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}

// MARK: - Route Helpers

enum RouteHelper {
    enum BodyAndToken {
        case success(body: Data, token: String)
        case error(Response)

        /// Convenience for `guard case` patterns -- returns the error response if this is `.error`.
        var errorResponse: Response {
            guard case let .error(response) = self else {
                fatalError("errorResponse called on .success -- this indicates a logic error in route handling")
            }
            return response
        }
    }

    /// Reads the request body and validates the Copilot token.
    static func requireBodyAndToken(
        _ request: Request,
        tokenManager: TokenManager,
    ) async throws -> BodyAndToken {
        var request = request
        let body = try await request.collectBody(upTo: 4 * 1_024 * 1_024)
        let bodyData = Data(body.readableBytesView)

        guard !bodyData.isEmpty else {
            return .error(ProxyResponse.error(status: .badRequest, message: "Missing request body"))
        }

        guard let token = await tokenManager.currentCopilotTokenString else {
            return .error(ProxyResponse.error(status: .unauthorized, message: "Not authenticated with Copilot"))
        }

        return .success(body: bodyData, token: token)
    }
}

// MARK: - Response Helpers

enum ProxyResponse {
    static func json(status: HTTPResponse.Status = .ok, data: Data) -> Response {
        Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(bytes: data)),
        )
    }

    static func json(status: HTTPResponse.Status = .ok, body: some Encodable & Sendable) -> Response {
        let data = (try? JSONEncoder().encode(body)) ?? Data()
        return json(status: status, data: data)
    }

    static func error(
        status: HTTPResponse.Status,
        message: String,
        extraHeaders: [HTTPField.Name: String] = [:],
    ) -> Response {
        struct ErrorBody: Encodable {
            let error: ErrorDetail
            struct ErrorDetail: Encodable {
                let message: String
                let type: String
            }
        }
        let body = ErrorBody(error: .init(message: message, type: "error"))
        let data = (try? JSONEncoder().encode(body)) ?? Data()

        var headers: HTTPFields = [.contentType: "application/json"]
        for (name, value) in extraHeaders {
            headers[name] = value
        }

        return Response(
            status: status,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(bytes: data)),
        )
    }

    static func sse(from bytes: URLSession.AsyncBytes, transform: (@Sendable (String) -> [String])? = nil) -> Response {
        let stream = AsyncStream<ByteBuffer> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }
                        let events: [String]
                        if let transform {
                            events = transform(line)
                        } else if !line.isEmpty {
                            events = ["data: \(line)\n\n"]
                        } else {
                            continue
                        }

                        for event in events {
                            var buf = ByteBuffer()
                            buf.writeString(event)
                            continuation.yield(buf)
                        }
                    }
                } catch {
                    // Stream ended or cancelled
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        return Response(
            status: .ok,
            headers: [
                .contentType: "text/event-stream",
                .cacheControl: "no-cache",
                .connection: "keep-alive",
            ],
            body: .init(asyncSequence: stream),
        )
    }
}

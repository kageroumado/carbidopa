import Foundation
import HTTPTypes
import Hummingbird
import os

/// Enforces a minimum interval between Copilot-bound requests.
///
/// When disabled or `minIntervalSeconds == 0`, every call to ``acquire()`` returns ``Decision/allow``.
/// Otherwise, requests are serialized so that each one starts at least `minIntervalSeconds` after the
/// previous one. Behavior on contention is controlled by ``mode``: in ``Mode/wait`` mode the limiter
/// reserves the next slot for the caller (who is expected to sleep); in ``Mode/reject`` mode the limiter
/// returns the remaining wait time so the caller can respond with `429 Too Many Requests`.
actor RateLimiter {
    /// Routes that are forwarded to Copilot and therefore count toward the rate limit.
    ///
    /// Local routes (`/`, `/token`, `/usage`, `/v1/messages/count_tokens`, `/v1/models`) are not limited.
    static let limitedPaths: Set<String> = [
        "/v1/chat/completions",
        "/v1/messages",
        "/v1/embeddings",
    ]

    enum Mode: String, Sendable, CaseIterable, Hashable {
        case wait
        case reject
    }

    enum Decision: Sendable, Equatable {
        case allow
        case wait(Duration)
        case reject(retryAfterSeconds: Int)
    }

    private(set) var isEnabled: Bool
    private(set) var minIntervalSeconds: Double
    private(set) var mode: Mode

    /// The earliest clock time at which the next request may proceed. Each granted request advances
    /// this by `minIntervalSeconds`, so concurrent callers naturally serialize onto successive slots.
    private var nextAvailableAt: ContinuousClock.Instant = .now

    init(isEnabled: Bool = false, minIntervalSeconds: Double = 30, mode: Mode = .wait) {
        self.isEnabled = isEnabled
        self.minIntervalSeconds = max(0, minIntervalSeconds)
        self.mode = mode
    }

    func configure(isEnabled: Bool, minIntervalSeconds: Double, mode: Mode) {
        self.isEnabled = isEnabled
        self.minIntervalSeconds = max(0, minIntervalSeconds)
        self.mode = mode
    }

    func acquire() -> Decision {
        guard isEnabled, minIntervalSeconds > 0 else { return .allow }

        let now = ContinuousClock.now
        let interval = Duration.seconds(minIntervalSeconds)

        if now >= nextAvailableAt {
            nextAvailableAt = now + interval
            return .allow
        }

        switch mode {
        case .wait:
            let slot = nextAvailableAt
            nextAvailableAt = slot + interval
            return .wait(now.duration(to: slot))
        case .reject:
            let remaining = now.duration(to: nextAvailableAt)
            // Round up so clients waiting on Retry-After don't immediately re-fire too early.
            let seconds = remaining.components.seconds + (remaining.components.attoseconds > 0 ? 1 : 0)
            return .reject(retryAfterSeconds: max(1, Int(seconds)))
        }
    }
}

// MARK: - Middleware

struct RateLimitMiddleware<Context: RequestContext>: RouterMiddleware {
    let limiter: RateLimiter
    private let logger = Logger.app(category: "RateLimit")

    func handle(
        _ request: HummingbirdCore.Request,
        context: Context,
        next: @concurrent (Request, Context) async throws -> Response,
    ) async throws -> Response {
        guard RateLimiter.limitedPaths.contains(request.uri.path) else {
            return try await next(request, context)
        }

        let decision = await limiter.acquire()
        switch decision {
        case .allow:
            return try await next(request, context)

        case let .wait(duration):
            logger.info("Rate limit: delaying \(request.uri.path) by \(duration, privacy: .public)")
            try await Task.sleep(for: duration)
            return try await next(request, context)

        case let .reject(retryAfter):
            logger.info("Rate limit: rejecting \(request.uri.path) (retry after \(retryAfter)s)")
            return ProxyResponse.error(
                status: .tooManyRequests,
                message: "Rate limit exceeded. Retry after \(retryAfter) seconds.",
                extraHeaders: [HTTPField.Name("Retry-After")!: "\(retryAfter)"],
            )
        }
    }
}

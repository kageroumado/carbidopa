import Foundation

@MainActor @Observable
final class LogStore {
    private(set) var entries: [RequestLog] = []
    private(set) var totalRequests = 0

    private let maxEntries = 50

    func append(_ entry: RequestLog) {
        entries.append(entry)
        totalRequests += 1
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    var recentEntries: [RequestLog] {
        Array(entries.suffix(5).reversed())
    }
}

struct RequestLog: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let method: String
    let path: String
    let statusCode: Int?
    let durationMs: Int
    let error: String?

    var isError: Bool {
        error != nil || (statusCode ?? 0) >= 400
    }

    var summary: String {
        let status = statusCode.map { "\($0)" } ?? "ERR"
        return "\(method) \(path) → \(status) (\(durationMs)ms)"
    }
}

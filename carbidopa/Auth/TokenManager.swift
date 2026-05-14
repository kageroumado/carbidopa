import Foundation
import os

actor TokenManager {
    private let logger = Logger.app(category: "TokenManager")

    private var githubToken: String?
    private var tokenSource: String?
    private var copilotToken: CopilotToken?
    private var refreshTask: Task<Void, Never>?

    var isAuthenticated: Bool {
        githubToken != nil && copilotToken != nil && !(copilotToken?.isExpired ?? true)
    }

    var currentCopilotTokenString: String? {
        copilotToken?.token
    }

    var currentGitHubToken: String? {
        githubToken
    }

    var currentTokenSource: String? {
        tokenSource
    }

    var tokenStatus: TokenStatus {
        if githubToken == nil { return .notFound }
        guard let ct = copilotToken else { return .loading }
        return ct.isExpired ? .expired : .valid
    }

    // MARK: - Lifecycle

    func loadAndRefresh() async {
        resolveGitHubToken()
        guard githubToken != nil else {
            logger.info("No GitHub token found from any source")
            return
        }
        do {
            try await exchangeToken()
            startRefreshLoop()
        } catch {
            logger.error("Initial token exchange failed: \(error)")
        }
    }

    func reloadToken() async {
        refreshTask?.cancel()
        refreshTask = nil
        copilotToken = nil

        resolveGitHubToken()
        guard githubToken != nil else {
            logger.info("No GitHub token found after reload")
            return
        }
        do {
            try await exchangeToken()
            startRefreshLoop()
        } catch {
            logger.error("Token exchange after reload failed: \(error)")
        }
    }

    // MARK: - Private

    private func resolveGitHubToken() {
        if let resolved = GitHubTokenSource.resolve() {
            githubToken = resolved.token
            tokenSource = resolved.source
            logger.info("GitHub token resolved from \(resolved.source)")
        } else {
            githubToken = nil
            tokenSource = nil
        }
    }

    private func exchangeToken() async throws {
        guard let ghToken = githubToken else {
            throw TokenManagerError.noGitHubToken
        }
        copilotToken = try await GitHubAPI.exchangeForCopilotToken(githubToken: ghToken)
        logger.info("Copilot token exchanged successfully, refreshes in \(self.copilotToken?.refreshIn ?? 0)s")
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            var backoff = 1

            while !Task.isCancelled {
                let refreshIn = await copilotToken?.refreshIn ?? 1_500
                let delay = max(refreshIn - 60, 60)

                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    break
                }

                do {
                    try await exchangeToken()
                    backoff = 1
                    logger.info("Copilot token refreshed")
                } catch {
                    logger.error("Token refresh failed: \(error), re-resolving token")
                    // Token may have been rotated by the IDE — re-resolve
                    await resolveGitHubToken()
                    if await githubToken != nil {
                        do {
                            try await exchangeToken()
                            backoff = 1
                            logger.info("Copilot token refreshed after re-resolve")
                            continue
                        } catch {
                            logger.error("Token exchange failed after re-resolve: \(error)")
                        }
                    }
                    try? await Task.sleep(for: .seconds(backoff))
                    backoff = min(backoff * 2, 60)
                }
            }
        }
    }
}

enum TokenStatus: Sendable {
    case notFound
    case loading
    case valid
    case expired
    case error(String)
}

enum TokenManagerError: Error {
    case noGitHubToken
}

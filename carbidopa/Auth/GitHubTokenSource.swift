import Foundation
import os

/// Resolves a GitHub token from existing Copilot installations and environment variables.
///
/// Resolution order:
/// 1. Environment variables: `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`
/// 2. `~/.config/github-copilot/apps.json` (written by Copilot IDE plugins)
/// 3. `~/.config/github-copilot/hosts.json` (manual configuration)
enum GitHubTokenSource {
    struct ResolvedToken: Sendable {
        let token: String
        let source: String
    }

    private static let logger = Logger.app(category: "GitHubTokenSource")

    static func resolve() -> ResolvedToken? {
        if let result = resolveFromEnvironment() { return result }
        if let result = resolveFromAppsJSON() { return result }
        if let result = resolveFromHostsJSON() { return result }
        return nil
    }

    // MARK: - Environment Variables

    private static let envKeys = ["COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"]

    private static func resolveFromEnvironment() -> ResolvedToken? {
        for key in envKeys {
            if let value = ProcessInfo.processInfo.environment[key],
               !value.isEmpty {
                logger.info("Resolved GitHub token from environment variable \(key)")
                return ResolvedToken(token: value, source: "env:\(key)")
            }
        }
        return nil
    }

    // MARK: - apps.json

    private static func resolveFromAppsJSON() -> ResolvedToken? {
        let url = configDirectory.appendingPathComponent("apps.json")
        guard let data = try? Data(contentsOf: url),
              let apps = try? JSONDecoder().decode([String: AppsEntry].self, from: data) else {
            return nil
        }

        // Find the first entry with an oauth_token
        for (_, entry) in apps {
            if let token = entry.oauthToken, !token.isEmpty {
                logger.info("Resolved GitHub token from apps.json")
                return ResolvedToken(token: token, source: "apps.json")
            }
        }
        return nil
    }

    // MARK: - hosts.json

    private static func resolveFromHostsJSON() -> ResolvedToken? {
        let url = configDirectory.appendingPathComponent("hosts.json")
        guard let data = try? Data(contentsOf: url),
              let hosts = try? JSONDecoder().decode([String: HostsEntry].self, from: data) else {
            return nil
        }

        // Prefer github.com entry
        if let entry = hosts["github.com"], let token = entry.oauthToken, !token.isEmpty {
            logger.info("Resolved GitHub token from hosts.json (github.com)")
            return ResolvedToken(token: token, source: "hosts.json")
        }

        // Fall back to any entry
        for (host, entry) in hosts {
            if let token = entry.oauthToken, !token.isEmpty {
                logger.info("Resolved GitHub token from hosts.json (\(host))")
                return ResolvedToken(token: token, source: "hosts.json")
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/github-copilot")
    }
}

// MARK: - JSON Models

private struct AppsEntry: Decodable {
    let oauthToken: String?

    enum CodingKeys: String, CodingKey {
        case oauthToken = "oauth_token"
    }
}

private struct HostsEntry: Decodable {
    let oauthToken: String?

    enum CodingKeys: String, CodingKey {
        case oauthToken = "oauth_token"
    }
}

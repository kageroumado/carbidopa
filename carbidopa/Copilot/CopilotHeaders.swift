import Foundation

/// Headers required by the GitHub Copilot API.
///
/// These are the standard API contract headers that all Copilot clients send (VSCode, Neovim,
/// JetBrains, etc.). They identify the integration type and API version — they are not
/// authentication credentials and do not constitute impersonation.
enum CopilotHeaders {
    static let integrationId = "vscode-chat"
    static let editorVersion = "vscode/1.99.0"
    static let pluginVersion = "copilot-chat/0.26.7"
    static let userAgent = "GitHubCopilotChat/0.26.7"
    static let apiVersion = "2025-04-01"

    static func buildHeaders(token: String, isVision: Bool = false) -> [String: String] {
        var headers: [String: String] = [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
            "copilot-integration-id": integrationId,
            "editor-version": editorVersion,
            "editor-plugin-version": pluginVersion,
            "User-Agent": userAgent,
            "x-github-api-version": apiVersion,
            "x-request-id": UUID().uuidString,
            "Accept": "application/json",
        ]
        if isVision {
            headers["copilot-vision-request"] = "true"
        }
        return headers
    }

    static func githubHeaders(token: String) -> [String: String] {
        [
            "Authorization": "token \(token)",
            "Accept": "application/json",
            "User-Agent": userAgent,
        ]
    }
}

import Foundation
import os

@MainActor @Observable
final class AppState {
    var serverRunning = false
    var serverPort: UInt16 = 4_141
    var tokenStatus: TokenStatus = .notFound
    var tokenSourceDescription: String?
    var lastError: String?
    var availableModels: [CopilotModel] = []
    var claudeCodeConfigured = false
    var configuredModel: String?
    var premiumQuota: PremiumQuota?

    var rateLimitEnabled: Bool {
        didSet {
            UserDefaults.standard.set(rateLimitEnabled, forKey: Self.rateLimitEnabledKey)
            applyRateLimitConfig()
        }
    }

    var rateLimitIntervalSeconds: Double {
        didSet {
            UserDefaults.standard.set(rateLimitIntervalSeconds, forKey: Self.rateLimitIntervalKey)
            applyRateLimitConfig()
        }
    }

    var rateLimitMode: RateLimiter.Mode {
        didSet {
            UserDefaults.standard.set(rateLimitMode.rawValue, forKey: Self.rateLimitModeKey)
            applyRateLimitConfig()
        }
    }

    let logStore = LogStore()

    private var server: ProxyServer?
    private var startTask: Task<Void, Never>?
    private let tokenManager = TokenManager()
    private let copilotClient = CopilotClient()
    private let rateLimiter: RateLimiter
    private let logger = Logger.app(category: "AppState")

    private static let settingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    private static let rateLimitEnabledKey = "rateLimit.enabled"
    private static let rateLimitIntervalKey = "rateLimit.intervalSeconds"
    private static let rateLimitModeKey = "rateLimit.mode"

    init() {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: Self.rateLimitEnabledKey)
        let interval = (defaults.object(forKey: Self.rateLimitIntervalKey) as? Double) ?? 30
        let mode = (defaults.string(forKey: Self.rateLimitModeKey)
            .flatMap(RateLimiter.Mode.init(rawValue:))) ?? .wait

        self.rateLimitEnabled = enabled
        self.rateLimitIntervalSeconds = interval
        self.rateLimitMode = mode
        self.rateLimiter = RateLimiter(isEnabled: enabled, minIntervalSeconds: interval, mode: mode)

        if let env = Self.readSettingsEnv(),
           env["ANTHROPIC_BASE_URL"] as? String == "http://localhost:\(serverPort)" {
            self.claudeCodeConfigured = true
            self.configuredModel = env["ANTHROPIC_MODEL"] as? String
        }
        self.startTask = Task { @MainActor in
            await self.start()
        }
    }

    private func applyRateLimitConfig() {
        let enabled = rateLimitEnabled
        let interval = rateLimitIntervalSeconds
        let mode = rateLimitMode
        Task { [rateLimiter] in
            await rateLimiter.configure(isEnabled: enabled, minIntervalSeconds: interval, mode: mode)
        }
    }

    func start() async {
        guard !serverRunning else { return }

        await tokenManager.loadAndRefresh()
        await updateTokenStatus()

        let proxyServer = ProxyServer(
            port: Int(serverPort),
            logStore: logStore,
            tokenManager: tokenManager,
            copilotClient: copilotClient,
            rateLimiter: rateLimiter,
        )
        server = proxyServer

        do {
            try await proxyServer.start()
            serverRunning = true
            lastError = nil
            logger.info("Server started on port \(self.serverPort)")
        } catch {
            lastError = error.localizedDescription
            serverRunning = false
            logger.error("Failed to start server: \(error)")
        }

        await fetchModels()
        await fetchQuota()
    }

    func stop() async {
        await server?.stop()
        server = nil
        serverRunning = false
    }

    func reloadToken() async {
        await tokenManager.reloadToken()
        await updateTokenStatus()
    }

    // MARK: - Models

    func fetchModels() async {
        guard let token = await tokenManager.currentCopilotTokenString else { return }

        do {
            let data = try await copilotClient.models(token: token)
            let response = try JSONDecoder().decode(CopilotModelsResponse.self, from: data)
            var seen = Set<String>()
            availableModels = response.data
                .filter { $0.capabilities?.type == "chat" }
                .sorted { ($0.vendor, $0.id) < ($1.vendor, $1.id) }
                .filter { seen.insert("\($0.vendor)/\($0.id)").inserted }
        } catch {
            logger.error("Failed to fetch models: \(error)")
        }
    }

    // MARK: - Quota

    func fetchQuota() async {
        guard let ghToken = await tokenManager.currentGitHubToken else { return }
        do {
            let userInfo = try await GitHubAPI.getUserInfo(githubToken: ghToken)
            if let premium = userInfo.quotaSnapshots?.premiumInteractions {
                premiumQuota = PremiumQuota(
                    used: premium.entitlement - premium.remaining,
                    total: premium.entitlement,
                    unlimited: premium.unlimited,
                )
            }
        } catch {
            logger.error("Failed to fetch quota: \(error)")
        }
    }

    // MARK: - Claude Code Settings

    func configureClaudeCode(model: String) {
        do {
            var settings: [String: Any] = [:]

            if FileManager.default.fileExists(atPath: Self.settingsURL.path) {
                let data = try Data(contentsOf: Self.settingsURL)
                if let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    settings = parsed
                }
            }

            var env = (settings["env"] as? [String: Any]) ?? [:]
            env["ANTHROPIC_BASE_URL"] = "http://localhost:\(serverPort)"
            env["ANTHROPIC_AUTH_TOKEN"] = "sk-dummy"
            env["ANTHROPIC_MODEL"] = model
            settings["env"] = env

            let dir = Self.settingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let output = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: Self.settingsURL)

            claudeCodeConfigured = true
            configuredModel = model
            logger.info("Claude Code settings updated with model \(model)")
        } catch {
            lastError = "Failed to update Claude Code settings: \(error.localizedDescription)"
            logger.error("Failed to write settings: \(error)")
        }
    }

    func removeClaudeCodeConfig() {
        do {
            guard FileManager.default.fileExists(atPath: Self.settingsURL.path) else { return }

            let data = try Data(contentsOf: Self.settingsURL)
            guard var settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            guard var env = settings["env"] as? [String: Any] else { return }

            env.removeValue(forKey: "ANTHROPIC_BASE_URL")
            env.removeValue(forKey: "ANTHROPIC_AUTH_TOKEN")
            env.removeValue(forKey: "ANTHROPIC_MODEL")

            if env.isEmpty {
                settings.removeValue(forKey: "env")
            } else {
                settings["env"] = env
            }

            let output = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: Self.settingsURL)

            claudeCodeConfigured = false
            configuredModel = nil
            logger.info("Claude Code proxy settings removed")
        } catch {
            lastError = "Failed to update Claude Code settings: \(error.localizedDescription)"
        }
    }

    private static func readSettingsEnv() -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = settings["env"] as? [String: Any] else {
            return nil
        }
        return env
    }

    private func updateTokenStatus() async {
        tokenStatus = await tokenManager.tokenStatus
        tokenSourceDescription = await tokenManager.currentTokenSource
    }
}

// MARK: - Copilot Models

struct CopilotModelsResponse: Decodable {
    let data: [CopilotModel]
}

struct PremiumQuota {
    let used: Int
    let total: Int
    let unlimited: Bool
}

struct CopilotModel: Decodable, Identifiable {
    let id: String
    let name: String
    let vendor: String
    let preview: Bool
    let capabilities: Capabilities?

    struct Capabilities: Decodable {
        let type: String?
    }
}

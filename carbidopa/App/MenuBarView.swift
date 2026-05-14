import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState
    @State private var showModels = false
    @State private var showLogs = false
    @State private var showRateLimit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusSection
            sectionDivider

            ClaudeCodeSection(appState: appState)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            sectionDivider

            modelsSection
            sectionDivider

            requestsSection
            sectionDivider

            rateLimitSection
            sectionDivider

            actionsSection
            sectionDivider

            LaunchAtLoginToggle()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            sectionDivider

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .keyboardShortcut("q")
        }
        .frame(width: 340)
    }

    // MARK: - Status (consolidated server + token)

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)
                Text(appState.serverRunning ? "Server Running" : "Server Stopped")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if let source = appState.tokenSourceDescription {
                    HStack(spacing: 4) {
                        Text("Token: \(source)")
                            .foregroundStyle(.secondary)
                        if let url = tokenFileURL(for: source) {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: {
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")
                        }
                    }
                }
            }

            if appState.serverRunning {
                HStack {
                    Text(verbatim: "Port \(appState.serverPort)")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let quota = appState.premiumQuota, !quota.unlimited {
                        Text("\(quota.used)/\(quota.total) premium")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if case .notFound = appState.tokenStatus {
                VStack(alignment: .leading, spacing: 3) {
                    Text("No GitHub token found. Either:")
                        .font(.callout)
                    Text("1. Install GitHub Copilot in an IDE")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("2. Set GITHUB_TOKEN or GH_TOKEN env var")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            if let error = appState.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Models

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showModels.toggle() }
            } label: {
                HStack {
                    Text("Available Models")
                    Spacer()
                    if !appState.availableModels.isEmpty {
                        Text("\(appState.availableModels.count)")
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showModels ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showModels {
                if appState.availableModels.isEmpty {
                    Text("No models loaded")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ModelsListView(
                        models: appState.availableModels,
                        activeModel: appState.configuredModel,
                        onSelectModel: { appState.configureClaudeCode(model: $0) }
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Requests

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showLogs.toggle() }
            } label: {
                HStack {
                    Text("Recent Requests")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showLogs ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showLogs {
                let entries = appState.logStore.recentEntries
                if entries.isEmpty {
                    Text("No requests yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(entries) { entry in
                            LogEntryRow(entry: entry)
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Rate Limit

    private var rateLimitSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showRateLimit.toggle() }
            } label: {
                HStack {
                    Text("Rate Limit")
                    Spacer()
                    if appState.rateLimitEnabled {
                        Text("\(Int(appState.rateLimitIntervalSeconds))s · \(appState.rateLimitMode == .wait ? "Wait" : "Reject")")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Off")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showRateLimit ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showRateLimit {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable rate limiting", isOn: $appState.rateLimitEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    if appState.rateLimitEnabled {
                        HStack {
                            Text("Min interval")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Stepper(
                                value: $appState.rateLimitIntervalSeconds,
                                in: 1 ... 300,
                                step: 1,
                            ) {
                                Text("\(Int(appState.rateLimitIntervalSeconds))s")
                                    .font(.system(.callout, design: .monospaced))
                                    .frame(minWidth: 36, alignment: .trailing)
                            }
                            .controlSize(.small)
                        }

                        HStack {
                            Text("When exceeded")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $appState.rateLimitMode) {
                                Text("Wait").tag(RateLimiter.Mode.wait)
                                Text("Reject").tag(RateLimiter.Mode.reject)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                            .labelsHidden()
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack {
            Button(appState.serverRunning ? "Stop Server" : "Start Server") {
                Task {
                    if appState.serverRunning {
                        await appState.stop()
                    } else {
                        await appState.start()
                    }
                }
            }
            .controlSize(.small)

            Spacer()

            Button("Reload Token") {
                Task { await appState.reloadToken() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var sectionDivider: some View {
        Divider()
            .padding(.horizontal, 12)
    }

    private var statusColor: Color {
        if !appState.serverRunning { return .red }
        switch appState.tokenStatus {
        case .valid: return .green
        case .loading: return .yellow
        case .notFound: return .orange
        case .expired, .error: return .red
        }
    }

    private func tokenFileURL(for source: String) -> URL? {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/github-copilot")
        switch source {
        case "apps.json": return configDir.appendingPathComponent("apps.json")
        case "hosts.json": return configDir.appendingPathComponent("hosts.json")
        default: return nil
        }
    }
}

// MARK: - Claude Code Section

private struct ClaudeCodeSection: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: appState.claudeCodeConfigured ? "link.circle.fill" : "link.circle")
                .font(.system(size: 22))
                .foregroundStyle(appState.claudeCodeConfigured ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code")
                if appState.claudeCodeConfigured, let model = appState.configuredModel {
                    Text(model)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if appState.claudeCodeConfigured {
                Button("Disconnect") {
                    appState.removeClaudeCodeConfig()
                }
                .controlSize(.small)
            } else {
                Button("Connect") {
                    if let firstModel = appState.availableModels.first {
                        appState.configureClaudeCode(model: firstModel.id)
                    }
                }
                .controlSize(.small)
                .disabled(appState.availableModels.isEmpty)
            }
        }
    }
}

// MARK: - Models List

private struct ModelsListView: View {
    let models: [CopilotModel]
    let activeModel: String?
    let onSelectModel: (String) -> Void

    @State private var copiedModelId: String?

    private var groupedModels: [(vendor: String, models: [CopilotModel])] {
        Dictionary(grouping: models, by: \.vendor)
            .sorted { $0.key < $1.key }
            .map { (vendor: $0.key, models: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(groupedModels, id: \.vendor) { group in
                Text(group.vendor)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)

                ForEach(group.models) { model in
                    ModelRow(
                        model: model,
                        isActive: model.id == activeModel,
                        isCopied: copiedModelId == model.id,
                        onCopy: { copyModel(model.id) },
                        onUse: { onSelectModel(model.id) }
                    )
                }
            }
        }
        .padding(.top, 4)
    }

    private func copyModel(_ id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
        copiedModelId = id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedModelId == id {
                copiedModelId = nil
            }
        }
    }
}

private struct ModelRow: View {
    let model: CopilotModel
    let isActive: Bool
    let isCopied: Bool
    let onCopy: () -> Void
    let onUse: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }

            Text(model.id)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if model.preview {
                Text("preview")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button(action: onCopy) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(isCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Copy model name")

            if !isActive {
                Button("Use", action: onUse)
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.borderless)
                    .help("Set as Claude Code model")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            isActive ? Color.accentColor.opacity(0.08) : .clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: RequestLog

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(entry.isError ? .red : .green)
                .frame(width: 6, height: 6)

            Text(entry.method)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)

            Text(entry.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let code = entry.statusCode {
                Text("\(code)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(code >= 400 ? .red : .secondary)
            }

            Text("\(entry.durationMs)ms")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .help(entryTooltip)
    }

    private var entryTooltip: String {
        var parts = [entry.summary]
        parts.append(entry.timestamp.formatted(.dateTime.hour().minute().second()))
        if let error = entry.error {
            parts.append("Error: \(error)")
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Launch at Login Toggle

private struct LaunchAtLoginToggle: View {
    @State private var launchAtLogin = false

    var body: some View {
        Toggle(isOn: $launchAtLogin) {
            HStack {
                Text("Launch at Login")
                Spacer()
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: launchAtLogin) { _, newValue in
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

# carbidopa

A native macOS menu-bar app that proxies GitHub Copilot through Anthropic and OpenAI API surfaces, so you can use Copilot as the backend for tools that speak those APIs — most notably **Claude Code**.

> Carbidopa is the drug that lets levodopa cross the blood–brain barrier intact. This app plays the same role: the actual work is done by Copilot, but it can only reach Claude Code (and other Anthropic/OpenAI-API clients) through a translator that prevents it from getting metabolized at the boundary.

Designed to be the simplest way to wire Copilot into Claude Code on a Mac: one click in the menu bar links the proxy to your `~/.claude/settings.json`. No CLI to install, no daemon to manage.

> [!IMPORTANT]
> This is an unofficial, reverse-engineered proxy. Read the **[Risks and ToS](#risks-and-tos)** section before using it. By running this you accept responsibility for how it interacts with your GitHub Copilot subscription.

## What it does

carbidopa runs a local HTTP server (default `http://127.0.0.1:4141`) that:

- Accepts **Anthropic Messages** requests (`POST /v1/messages`) and translates them to OpenAI Chat Completions before forwarding to Copilot. Responses are translated back to the Anthropic shape. Streaming, tool use, vision (images), system prompts, and stop sequences are all supported.
- Accepts **OpenAI Chat Completions** requests (`POST /v1/chat/completions`) and forwards them as-is.
- Forwards `POST /v1/embeddings` to Copilot.
- Lists available Copilot models at `GET /v1/models`.
- Provides local helpers: `GET /usage` (premium-interaction quota), `GET /token` (token status), `POST /v1/messages/count_tokens`, `GET /` (health check).

## Why a separate Swift app vs. the TypeScript copilot-api

This project is heavily inspired by [copilot-api](https://github.com/copilot-api/copilot-api), which solves the same problem in Node/Bun. If you want a cross-platform CLI with provider routing, manual approval flows, and a usage dashboard, use that.

carbidopa is the **native macOS** alternative for people who already live in Claude Code:

- Menu-bar app instead of a CLI — no Bun/Node install, no terminal session to keep alive.
- One-click **Connect to Claude Code** writes `ANTHROPIC_BASE_URL`/`ANTHROPIC_MODEL` to `~/.claude/settings.json`.
- Reads the GitHub token your IDE already stored — **no device-flow login that impersonates the VSCode OAuth client**. (See [Authentication](#authentication) below.)
- Native quota display, request log, launch-at-login, automatic token refresh.

It is intentionally narrower in scope: no rate-limit dashboards, no provider routing, no per-account UI.

## Installation

Requires macOS 26.0+ (Tahoe) and Xcode 26+.

```sh
git clone https://github.com/kageroumado/carbidopa.git
cd carbidopa
open carbidopa.xcodeproj
```

Build and run from Xcode. The app lives in the menu bar — there is no Dock icon. On first launch it will look for an existing Copilot token (see below); if none is found it shows instructions in the popup.

There is no signed release build yet. Build it yourself or ad-hoc sign your own.

## Authentication

carbidopa does **not** do its own OAuth or device-code flow. Instead, it reads the GitHub token your existing Copilot installation already stored. The token resolution order is:

1. Environment variables: `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`.
2. `~/.config/github-copilot/apps.json` (written by the official Copilot plugins in VSCode, Neovim, JetBrains, etc.).
3. `~/.config/github-copilot/hosts.json`.

This is a deliberate design choice. The GitHub Copilot device flow that other proxies use depends on the **VSCode OAuth client ID** — calling it from a third-party app is a form of OAuth-client impersonation that violates GitHub's developer terms. By reading the token your real Copilot plugin already obtained, the proxy stays out of the OAuth layer entirely.

**You need to have installed and signed into GitHub Copilot in at least one IDE for this to work.**

The GitHub token is exchanged for a short-lived Copilot session token at `api.github.com/copilot_internal/v2/token`. The session token is refreshed ~60s before expiry.

## Connecting Claude Code

In the menu-bar popup, click **Connect** in the "Claude Code" section. This writes the following to `~/.claude/settings.json`:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:4141",
    "ANTHROPIC_AUTH_TOKEN": "sk-dummy",
    "ANTHROPIC_MODEL": "<model-id>"
  }
}
```

`ANTHROPIC_AUTH_TOKEN` is a placeholder — Claude Code refuses to start without one, but the proxy ignores it. The model can be changed from the menu's **Available Models** list.

**Disconnect** removes those three keys and leaves the rest of your `settings.json` untouched.

## Rate limiting

To reduce the chance of triggering Copilot's abuse detection (see [Risks](#risks-and-tos)), you can enable a minimum interval between requests sent upstream. In the popup, expand **Rate Limit**:

- **Min interval**: minimum seconds between Copilot-bound requests. Default 30s.
- **When exceeded**:
  - **Wait** — the proxy holds the request until the next slot, then forwards it. Clients see latency, not errors.
  - **Reject** — the proxy returns `429 Too Many Requests` with a `Retry-After` header. Use this for clients that handle backoff themselves.

Rate limiting applies only to upstream-bound routes (`/v1/chat/completions`, `/v1/messages`, `/v1/embeddings`). Local routes (`/v1/models`, `/usage`, `/token`, `/v1/messages/count_tokens`, `/`) are never limited.

## Risks and ToS

You should understand what running this app means before you do it.

**It is unsupported and reverse-engineered.** GitHub Copilot is documented as a product for use *inside* official Copilot integrations (VSCode, JetBrains, Neovim, GitHub Mobile, etc.). Using its endpoints from anywhere else is not a documented or supported use case. This proxy can break at any time when GitHub changes its API.

**The proxy claims to be VSCode when talking to Copilot.** Specifically, requests to the Copilot API include:

- `copilot-integration-id: vscode-chat`
- `editor-version: vscode/1.99.0`
- `editor-plugin-version: copilot-chat/0.26.7`
- `User-Agent: GitHubCopilotChat/0.26.7`

These headers are not authentication credentials — they identify the integration type, and Copilot refuses requests without them. Every alternative client (including [copilot-api](https://github.com/copilot-api/copilot-api), `aider`, `continue.dev`'s Copilot adapter, and others) sends the same shape because Copilot's gateway hard-checks them. This proxy follows the same convention rather than inventing a distinct integration ID that would simply be rejected.

That said: this *is* impersonation, even if it's instrumental. We disclose it openly and you should weigh it before running the proxy.

**Abuse detection can suspend your Copilot subscription.** GitHub watches for traffic patterns that don't look like a human in an editor: high request volume, requests outside business hours, identical prompts, very long context windows, parallel sessions across many machines. There are documented cases of accounts being suspended for using third-party Copilot clients heavily. Enabling rate limiting (above) reduces but does not eliminate this risk. **Do not use this for automated batch workloads.**

**This is not a way to share a Copilot seat.** Your Copilot subscription is licensed to you. Configuring this proxy to serve external clients, share it with other people, or proxy traffic for other users is a violation of GitHub's Terms of Service.

**Privacy.** Request bodies pass through this proxy on their way to GitHub. The proxy does not log request or response *contents*, only metadata (method, path, status, duration). Your prompts go to GitHub and from there to Copilot's upstream model providers under [GitHub's data handling policies](https://docs.github.com/en/copilot/responsible-use-of-github-copilot-features).

**By using this software you accept these risks.** The license disclaims all warranties.

## Project layout

```
carbidopa/
├── App/             SwiftUI menu bar UI, AppState, log store
├── Auth/            GitHub token resolution + Copilot token exchange
├── Copilot/         HTTP client + canonical request headers
├── Server/          Hummingbird HTTP server, rate limiter, middleware
├── Routes/          Per-endpoint request handlers
├── Translation/     Anthropic ↔ OpenAI message translation
└── Utilities/       Logger helpers
```

## Acknowledgements

- [copilot-api](https://github.com/copilot-api/copilot-api) by the copilot-api maintainers (forked from `ericc-ch/copilot-api`) — the TypeScript proxy that established the patterns used here. Their handling of headers, streaming translation, and tool-use mapping was the reference implementation.
- [Hummingbird](https://github.com/hummingbird-project/hummingbird) — the Swift HTTP server framework powering the proxy.

## License

[MIT](LICENSE).

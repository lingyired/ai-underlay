# Privacy & Permissions

## What this app reads

| Data | Source | Leaves the machine? |
|---|---|---|
| Quota percentages, reset times | CodexBar CLI (local) | No |
| Codex lifecycle and pending-request metadata | Local Codex Desktop IPC; SQLite / rollout fallback | No |
| Claude lifecycle events | Local session logs; optional Claude Code hooks | No |
| Menu bar geometry | Window server (`CGWindowListCopyWindowInfo`) | No |
| Download counts (opt-in) | `GET` on the user's own stats endpoint (default lingai.net) | The request leaves the machine; it carries no user data — no identifiers, no cookies, just the URL |

## What this app never does

- No telemetry, no analytics, no phone-home. There is no server.
- The optional download monitor (设置 → 下载监控) is **off by default**. When
  switched on it only issues plain `GET` requests for aggregate counts and
  sends nothing about the user. It exists so the landing page's netdisk
  download clicks can be watched from the menu bar; the endpoint is ling's own
  service, configurable, and the switch stops all traffic immediately.
- Conversation content is not logged, persisted, or sent by the Codex runtime
  adapter. Desktop packets and local log records can contain content while
  being decoded in memory; the runtime projection retains only lifecycle,
  pending-request identifiers, and source/model metadata. The activity model
  has no prompt, tool-argument, or response fields.
- No reading of browser cookies, keychain secrets, or credentials. Credentials
  are handled entirely by the CodexBar CLI and the agents themselves.
- No silent configuration changes. `~/.claude/settings.json` is only modified
  after an explicit preview + confirm, and only entries bearing our marker are
  ever added or removed. Codex activity does not install hooks or change Codex
  settings; removing old AI Underlay Codex hooks requires a separate user
  action and backs up the configuration first.

## Permissions

The overlay uses **only public APIs** and requires **no** screen-recording
permission: window bounds and layer numbers are public; only window *titles*
would require screen recording, and we never read them.

- Screen Recording: not required, not requested.
- Accessibility: not required.
- Full Disk Access: not required.

## Files this app writes

| Path | Purpose | Permissions |
|---|---|---|
| `~/Library/Application Support/com.lingsmbp.aiunderlay/settings.json` | non-secret settings | default |
| `~/Library/Application Support/com.lingsmbp.aiunderlay/agent.sock` | local agent event socket | `0600`, owner only |
| `~/Library/Application Support/com.lingsmbp.aiunderlay/Engines/CodexBar/…` | app-managed CLI (GitHub builds only) | `0755` |
| `~/.claude/settings.json` | only when the user installs/removes hooks | user's file; a `.bak.<ts>` backup is written first |
| `~/.codex/hooks.json` | only when the user removes legacy app hooks | backup before cleanup; no new Codex hooks |

## Diagnostics

The Diagnostics tab can copy a report. Before copying, the text is run through
the same desensitizer used for CLI logs, which strips emails, tokens, and long
opaque identifiers.

## Codex connection boundary

The adapter connects only to the current user's owner-only local Unix socket,
uses bounded frames and revision checks, and follows existing thread streams.
It never starts/resumes a turn, answers a question, approves a tool, or connects
to a remote host. The internal protocol may change; log fallback remains active.

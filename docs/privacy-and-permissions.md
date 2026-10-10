# Privacy & Permissions

## What this app reads

| Data | Source | Leaves the machine? |
|---|---|---|
| Quota percentages, reset times | CodexBar CLI (local) | No |
| Agent lifecycle events (provider, session id, event kind, time) | Claude Code / Codex hooks | No |
| Menu bar geometry | Window server (`CGWindowListCopyWindowInfo`) | No |

## What this app never does

- No telemetry, no analytics, no phone-home. There is no server.
- No conversation content: the agent event type has **no field** for prompts,
  tool arguments, or model output. It cannot carry them.
- No reading of browser cookies, keychain secrets, or credentials. Credentials
  are handled entirely by the CodexBar CLI and the agents themselves.
- No silent configuration changes. `~/.claude/settings.json` is only modified
  after an explicit preview + confirm, and only entries bearing our marker are
  ever added or removed.

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
| `~/.claude/settings.json` | only when the user installs hooks | user's file; a `.bak.<ts>` backup is written first |

## Diagnostics

The Diagnostics tab can copy a report. Before copying, the text is run through
the same desensitizer used for CLI logs, which strips emails, tokens, and long
opaque identifiers.
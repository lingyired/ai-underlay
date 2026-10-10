# Agent Capability Report (P0-5)

> Produced during P0 to establish, before any integration work, exactly which
> agent states can be observed accurately and which must degrade to `unknown`.

## Sources consulted

- CodeStatus (reference implementation), `henriquegpb/codestatus`, MIT license.
  macOS app is Swift 6 / AppKit; uses the agents' **official lifecycle hooks**
  as the source of truth and explicitly refuses to infer completion from
  process quiet. States: free / busy / needs-approval / needs-answer / failed,
  with `Unknown` and `Reconnecting` fallbacks.
- Claude Code hooks reference: https://docs.claude.com/en/docs/claude-code/hooks
- CodexBar CLI 0.58.0 (this machine) — unrelated to agent state, listed for completeness.

## Reuse decision

CodeStatus is MIT and architecturally aligned (hook-driven, honesty rules).
We will **port a minimal hook-event vocabulary and a session reducer**, not
copy its app/UI. Recorded upstream reference: `henriquegpb/codestatus` (pin the
tag/commit at P3 time). The event whitelist we adopt is our own
(`AIUnderlayKit/Agent/AgentEvent.swift`), derived from the Claude Code hook
reference below.

## Capability matrix (per host)

| Host | running | waitingApproval | waitingInput | Notes |
|---|---|---|---|---|
| Claude Code CLI | ✅ | ✅ | ✅ | Full support. Hooks: `UserPromptSubmit`, `PreToolUse`, `PostToolUse` → running; `PermissionRequest` / interactive `PreToolUse` → waitingApproval; `Notification` → waitingInput; `Stop` → completed; `SessionStart`/`SessionEnd` → lifecycle. |
| Codex CLI | ✅ | ✅ (when emitted) | ❌ → `unknown` | Busy and identifiable approval are observable. Free-text "waiting for an answer" is **not** reliably observable — must show `unknown`, never an orange waiting light. |
| Codex VS Code | unverified | unverified | unverified | Do not extrapolate CLI results to this host. Mark as unverified until measured. |

## Honesty rules (non-negotiable)

1. Never infer `completed`/`idle` from CPU activity or from silence. Use
   `unknown` or `reconnecting`.
2. `waitingInput` is only shown when a host genuinely emits an observable
   "needs an answer" event. Codex does not → `unknown`.
3. `AgentConfidence.inferred` states are presented with a hedge in the UI.
4. No event carries prompt text, tool arguments, or model output — the event
   type has no field for them.

## Event → state mapping (Claude Code CLI)

| Hook event | AgentEventKind | AgentState |
|---|---|---|
| SessionStart | sessionStart | idle |
| UserPromptSubmit | userPromptSubmitted | running |
| PreToolUse | toolUseStarted | running |
| PostToolUse | toolUseFinished | running |
| PermissionRequest | permissionRequested | waitingApproval |
| Notification | notification | waitingInput |
| Stop | stopped | completed |
| SessionEnd | sessionEnd | idle |
| (unrecognized) | unknown | unknown |

## Open items carried into P3

- Confirm exact hook payload fields on the installed Claude Code version.
- Confirm whether Codex emits an approval hook on the installed version.
- Decide the socket path and event framing (newline-delimited JSON).

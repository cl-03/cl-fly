# Chat UI and Session Logic Spec (Telegram + WhatsApp Blend)

## Goal
Build a customer-service chat experience that combines:
- Telegram strengths: high information density, fast triage, strong session controls.
- WhatsApp strengths: low cognitive load, clear delivery status, reliable offline behavior.

See also: `docs/chat-ui-benchmark-other-systems.md` for broader industry patterns (Intercom/Zendesk/Freshdesk/Crisp/Drift) and implementation priorities for cl-fly.

## Information Architecture
- Desktop: 3-pane layout.
  - Left pane: session list.
  - Center pane: message thread.
  - Right pane: session details and actions (collapsible).
- Mobile: 2-layer flow.
  - Session list first.
  - Full-screen thread after entering a session.

## Session List Contract
Each session row should contain:
- Session display name/ID.
- Last message snippet.
- Last activity time.
- Unread count badge.
- Failed-send badge.
- Optional typing snippet.

Priority ordering:
1. Manual pinned sessions.
2. Sessions with failed outbound messages.
3. Unread sessions.
4. Typing-active sessions (short boost window).
5. Latest activity time.

## Message Status Model
Use a single state machine vocabulary across visitor and agent UIs:
- queued
- sending
- sent
- delivered (optional extension)
- read (optional extension)
- failed

Rules:
- Every outbound message must carry clientMsgId.
- clientMsgId is the reconciliation key for ws/http ack and dedup.
- Status transitions must be idempotent.

## Retry Model
- Auto retry: exponential backoff + jitter.
- Retry controls: pause/resume auto retry, retry-one, retry-batch, retry-by-error-type.
- Error categories:
  - ws-timeout
  - network
  - other
- Failed item UI should show:
  - Retry count.
  - Last error.
  - Next automatic retry ETA.

## Offline and Draft Model
- Per-session draft persistence in localStorage.
- Outbox persistence in localStorage.
- On reconnect:
  1. Restore context.
  2. Flush outbox.
  3. Pull incremental history.
  4. Merge and deduplicate.

## Presence and Typing
- Typing should be short-lived, throttled, and auto-expire.
- Presence should show online/offline plus last active timestamp.

## Metrics and Observability
Agent-side 5-minute panel:
- Failure rate.
- Average retries.
- Recovery rate.
- Top error type.

Visitor-side 5-minute panel:
- Delivery success rate.
- Average delivery latency.
- Failure count.

Export:
- Agent retry metrics must support CSV export.

## Copy and Terminology Rules
Use consistent Chinese terminology:
- "发送队列" instead of mixing with "重发队列".
- "发送成功/发送失败/发送中" for message status copy.
- "自动重试" for scheduler behavior.
- "离线保护" for offline queue behavior.

## Acceptance Checklist
- No message loss after 30s offline and reconnect.
- No duplicate sends after retry and reconnect.
- Failed message shows reason and retry action within 1s.
- Session failed badge equals actual failed pending count.
- 5-minute metrics align with event logs.

## Implementation Status (P0)
As of 2026-03-26, the first operations slice is implemented in cl-fly:

- Session SLA clock model is live:
  - first reply SLA and next reply SLA timers are tracked in session state.
  - each session snapshot includes a normalized `sla` block with state and due-at metadata.
- Agent inbox API now includes:
  - per-session SLA data.
  - aggregate SLA summary (`healthy`, `atRisk`, `breached`).
  - workload summary for online agents and current agent load/capacity.
- Agent workstation UI now includes:
  - top chips for SLA and workload status.
  - failed/unread/read grouped rendering.
  - upgraded ordering: failed > unread > SLA risk > latest activity (while retaining secondary typing/pinned behavior).

P0 validation record:
- static checks on modified files: passed.
- full test suite execution: passed (`All requested test suites executed.`).

Next planned slice (P1):
- Macro engine (template + actions).
- Session attribute schema/filtering.
- Internal notes with @mention.

## Implementation Status (P1)
As of 2026-03-26, P1 is partially implemented in cl-fly:

- Backend contract delivered:
  - macro core (`create-macro`, `list-macros`) and action schema validation (`setTag`, `setPriority`, `assignTo`, `setStatus`).
  - session attribute core (`set/get/list/find`) with combined filtering across `issueType`, `urgency`, `language`, `customerTier`.
  - HTTP APIs:
    - `GET/POST /api/v1/macros`
    - `GET/PUT /api/v1/sessions/attributes` (single-session mode + filter list mode)
- Contract tests delivered:
  - positive path coverage for macro and attributes APIs.
  - negative path coverage for invalid macro action schema.
  - attribute combined-filter coverage.
- Agent demo minimal integration delivered:
  - macro select + insert-to-composer action.
  - session attribute filter panel (4 dimensions) with apply/clear.
  - inbox rendering now supports attribute-filtered session scope.

Remaining P1 item:
- None. P1 scope is fully implemented.

Internal notes + @mention delivery notes:
- Agent can send `internal_note` messages (agent-only).
- Visitor message list hides `internal_note` entries by default (`viewerType=visitor`).
- `@mention` tokens are extracted and returned in message payload (`mentions` array).
- Agent demo supports dedicated "发送内部备注" action and renders internal-note timeline chips.

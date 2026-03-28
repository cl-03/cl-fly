# Online Support System Benchmark (Beyond Telegram/WhatsApp)

## Scope
This benchmark extends the existing Telegram/WhatsApp UI spec by comparing agent-workflow patterns from:
- Intercom
- Zendesk
- Freshdesk / Freshchat
- Crisp
- Drift (Salesloft)

The goal is to extract high-impact patterns that can be absorbed into cl-fly with low implementation risk.

## Sources (Representative)
- Intercom Inbox setup and Workflows collection
- Zendesk routing and productivity guides
- Freshdesk/Freshchat knowledge base categories (workflow, analytics, channels)
- Drift product overview under Salesloft (qualification/routing/ROI)

## Cross-Product Patterns Worth Absorbing

### 1) Triage and Work Distribution
Observed pattern:
- Mature systems support both push routing (system assigns) and pull routing (agents self-assign from views/queues).
- Capacity-aware assignment is a recurring design (agent availability + load limits).
- Queue segmentation is based on channel/topic/region/skills.

Absorb into cl-fly:
- Add assignment modes:
  - auto-balanced (push)
  - queue-pick (pull)
- Add per-agent concurrency cap (default 3 active sessions).
- Add queue dimensions in session metadata: channel, topic, region, skillTag.

### 2) SLA/Response-Time Contracts
Observed pattern:
- Response promises are explicit and visible (first response / next response / resolution timers).
- SLA state is used in queue views and automation rules.

Absorb into cl-fly:
- Add session-level SLA clocks:
  - firstReplyDueAt
  - nextReplyDueAt
- Show SLA badge in session list with 3 states:
  - healthy
  - at-risk
  - breached
- Allow SLA-driven sort boost and escalation trigger.

### 3) Macros and One-Click Actions
Observed pattern:
- Macros combine text snippets + workflow actions (tag/assign/snooze/close).
- High agent efficiency comes from action bundling, not just canned text.

Absorb into cl-fly:
- Introduce macro object:
  - title
  - replyTemplate
  - actions[] (setTag, setPriority, assignTo, setStatus)
- Add quick apply in composer and slash-command support (/macro-name).

### 4) Data Attributes and Reporting Discipline
Observed pattern:
- Conversation attributes + tags are first-class reporting dimensions.
- Teams monitor transfer/touches/reopen/failure rates, not only reply speed.

Absorb into cl-fly:
- Add structured session attributes:
  - issueType
  - urgency
  - language
  - customerTier
- Add operational metrics:
  - handoffCount
  - reopenCount
  - avgFirstReplyMs
  - queueWaitMs

### 5) Collaboration Layer
Observed pattern:
- Internal collaboration primitives are explicit: notes, @mentions, side conversations.
- Collaboration events are auditable in the timeline.

Absorb into cl-fly:
- Add internal-only note events in message timeline.
- Add @mention in internal note text.
- Add handoff note requirement when transferring ownership.

### 6) Knowledge-Assist in Context
Observed pattern:
- Agents can open knowledge snippets without leaving the conversation.
- Suggestion quality improves with issue attributes/tags.

Absorb into cl-fly:
- Add right-rail "knowledge quick panel" with search.
- Save frequently used snippets per issueType.
- Support insertion with placeholders (customerName, orderId, etc.).

### 7) Commercial Chat Qualification Patterns (Drift-like)
Observed pattern:
- Visitor qualification and intent capture happen very early.
- High-intent visitors are routed fast to human agents or meeting booking.

Absorb into cl-fly:
- Add optional pre-chat card:
  - intent
  - company
  - role
  - urgency
- Prioritize queues using intent score and customer tier.

## Gap vs Current cl-fly State
Already strong:
- Multi-session workspace
- Send-state reliability (queued/sending/sent/failed)
- Retry controls and retry analytics (5m + CSV)
- Offline protection and reconnect flush

Primary gaps:
- No formal SLA model
- No routing strategy framework (push/pull/capacity)
- No macro/action-bundle system
- Limited collaboration semantics (internal notes/mentions)
- No first-class session attribute taxonomy

## Proposed Implementation Roadmap

### P0 (1-2 iterations)
- Add SLA chip + overdue sorting
- Add assignment mode switch (manual pick vs balanced)
- Add agent concurrency cap and visible workload chip

Acceptance:
- Overdue sessions surface within 1s of threshold breach.
- In balanced mode, active session counts per agent remain within cap +/-1 under burst load.

Status:
- Partial complete in current cl-fly implementation:
  - SLA clock + SLA chip + SLA-aware sorting are implemented.
  - workload visibility is implemented in agent inbox/API and agent-demo chips.
- Not yet complete:
  - assignment mode switch (manual pick vs balanced).
  - enforced routing-level concurrency cap policy.

### P1 (2-3 iterations)
- Add macro engine (template + actions)
- Add session attributes schema and filters
- Add internal notes with @mention

Acceptance:
- Top-10 repetitive replies can be executed in <=2 clicks.
- Attribute-based filtering supports at least 4 dimensions with combined predicates.

Status:
- Partial complete in current cl-fly implementation:
  - macro backend contract is implemented with action schema validation.
  - session attributes backend contract and 4-dimension combined filtering are implemented.
  - agent-demo has minimal macro insert and attribute filter UI wiring.
- Completed in this iteration:
  - internal notes with `@mention` workflow and timeline semantics.

### P2 (later)
- Add pre-chat qualification card and intent routing score
- Add knowledge quick panel with snippet insertion
- Extend analytics with handoff/reopen/touches dashboards

Acceptance:
- Qualified/high-intent sessions get priority boost and reduced first-reply time.
- Agent handling time improves for repeated intents after snippet adoption.

## UX Guardrails
- Keep state vocabulary consistent with existing spec:
  - 发送队列 / 发送中 / 发送成功 / 发送失败 / 离线保护 / 自动重试
- Avoid adding heavy workflow UI before visibility primitives (SLA + workload + queue filters) are in place.
- Keep routing explainable: every auto-assignment should expose the reason (capacity, skill, SLA risk, priority).

## Suggested Next Build Slice
Implement the smallest high-leverage package first:
1. SLA clock fields in session model + API exposure
2. Agent list workload counters
3. Session list sort key extension (failed > unread > SLA at-risk > latest)
4. One compact SLA/workload strip in agent-demo header

This slice gives immediate operational value and prepares the architecture for macros and advanced routing.

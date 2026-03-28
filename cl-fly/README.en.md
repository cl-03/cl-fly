# cl-fly

Common Lisp online customer support backend (HTTP + WebSocket), built with a spec-driven workflow.

## 1. Overview

cl-fly provides a multi-role customer service backend with:

- Visitor session initialization and real-time messaging
- Agent authentication, takeover, transfer, and inbox analytics
- Runtime configuration and blacklist management
- Attachment upload/send flow with validation policies
- Presence/typing snapshots for chat UX
- Contract/integration/performance gates for release quality

## 2. Main Capabilities

### Visitor / Session

- Session lifecycle: queued -> active -> closed
- Message deduplication by sessionId + clientMsgId
- Recent message replay
- Session presence and typing snapshots

### Agent

- JWT login and password change
- Session accept and transfer
- Agent inbox with analytics blocks
- Quick replies, macros, and session attributes

### Admin / Operations

- Runtime config read/write APIs
- Blacklist add/check
- Stats overview endpoint
- Default admin bootstrap (admin/admin123) with change-password flow

### Reliability / Security

- HTTP rate limiting (auth/messages/upload)
- Input validation (type/length)
- Upload policy checks (file type/size)
- Security and audit logging hooks

## 3. Tech Stack

- Language: Common Lisp (SBCL)
- HTTP server: Hunchentoot
- JSON: Jonathan
- DB: PostgreSQL (Postmodern)
- Socket: usocket + custom WS server
- Concurrency: bordeaux-threads
- Tests: FiveAM
- Dependency bootstrap: Quicklisp

ASD file: [cl-fly/cl-fly.asd](cl-fly/cl-fly.asd)

## 4. Project Structure

```text
cl-fly/
├── src/
│   ├── api/
│   ├── auth/
│   ├── core/
│   ├── infra/
│   ├── package.lisp
│   └── app.lisp
├── migrations/
├── static/site/
├── tests/
│   ├── contract/
│   ├── integration/
│   ├── unit/
│   ├── perf/
│   └── run-tests.lisp
├── docs/
├── start-server.lisp
└── README.md
```

## 5. Prerequisites

- SBCL 2.4+
- Quicklisp
- PostgreSQL 15+ (recommended)

## 6. Environment Variables

Defined in [cl-fly/src/infra/config.lisp](cl-fly/src/infra/config.lisp).

| Variable | Default | Description |
|---|---|---|
| KEFU_HTTP_PORT | 4000 | HTTP port |
| KEFU_WS_PORT | 4001 | WebSocket port |
| KEFU_DB_DSN | postgres://localhost:5432/cl_kefu | PostgreSQL DSN |
| KEFU_JWT_SECRET | dev-only-secret | JWT signing secret |
| KEFU_ENV | development | Runtime environment |
| KEFU_FILE_STORE | ./uploads | Upload storage path |
| KEFU_ADMIN_USERNAME | admin | Bootstrap admin username |
| KEFU_ADMIN_PASSWORD | admin123 | Bootstrap admin password |
| QUICKLISP_SETUP | none | Optional quicklisp setup path |
| KEFU_ENABLE_RELEASE_GATES | 0 | Enable release smoke gate |
| KEFU_ENABLE_PERF_BASELINE | 0 | Enable SC-001 baseline sampling |

## 7. Quick Start

### 7.1 Database

Create database:

```sql
CREATE DATABASE cl_kefu;
```

Run migrations:

```powershell
sbcl --load cl-fly/src/infra/migration.lisp --eval "(cl-fly.migration:up)" --quit
```

### 7.2 Start Service

Option A (recommended):

```powershell
sbcl --script cl-fly/start-server.lisp
```

Option B:

```powershell
sbcl --load cl-fly/src/app.lisp --eval "(cl-fly.app:start)"
```

After startup:

- HTTP: http://127.0.0.1:4000
- Health: GET /health
- Visitor WS: ws://127.0.0.1:4001/ws/visitor
- Agent WS: ws://127.0.0.1:4001/ws/agent
- Demo pages:
  - http://127.0.0.1:4000/chat
  - http://127.0.0.1:4000/agent-demo

## 8. HTTP and WS Contracts

### 8.1 Key HTTP Endpoints

Defined in [cl-fly/src/api/http-routes.lisp](cl-fly/src/api/http-routes.lisp).

- GET /health
- GET/POST /api/v1/config
- POST /api/v1/blacklist
- GET /api/v1/blacklist/check
- GET /api/v1/stats/overview
- GET/POST /api/v1/sessions
- GET /api/v1/agent/inbox
- GET/POST /api/v1/messages
- GET /api/v1/sessions/presence
- GET /api/v1/sessions/typing
- POST /api/v1/files/upload
- POST /api/v1/auth/login
- POST /api/v1/auth/change-password
- GET/POST /api/v1/quick-reply-groups
- GET/POST /api/v1/quick-replies
- GET /api/v1/knowledge/snippets
- GET/POST /api/v1/macros
- GET/POST /api/v1/sessions/attributes
- GET/POST /api/v1/agents/presence

### 8.2 WebSocket Contract

See [specs/001-cl-online-kefu/contracts/websocket-events.md](specs/001-cl-online-kefu/contracts/websocket-events.md).

- Visitor endpoint: /ws/visitor
- Agent endpoint: /ws/agent
- Envelope: event, requestId, timestamp, payload

## 9. Tests and Quality Gates

Unified test entry: [cl-fly/tests/run-tests.lisp](cl-fly/tests/run-tests.lisp)

```powershell
sbcl --script cl-fly/tests/run-tests.lisp
```

The runner:

- Bootstraps Quicklisp dependencies automatically
- Runs contract/integration/unit suites
- Runs perf gates:
  - SC-001: tests/perf/perf_ws_200_concurrency.lisp
  - SC-002: tests/perf/perf_first_message_success_rate.lisp

Enable release smoke gate:

```powershell
$env:KEFU_ENABLE_RELEASE_GATES='1'
sbcl --script cl-fly/tests/run-tests.lisp
```

Enable SC-001 baseline sampling:

```powershell
$env:KEFU_ENABLE_PERF_BASELINE='1'
$env:KEFU_SC001_BASELINE_SAMPLES='5'
sbcl --script cl-fly/tests/run-tests.lisp
```

Reports:

- cl-fly/tests/perf/reports/sc001-latest.txt
- cl-fly/tests/perf/reports/sc002-latest.txt
- cl-fly/tests/perf/reports/sc001-baseline-latest.txt

## 10. Deployment (Nginx)

Deployment and smoke-check guidance:

- [specs/001-cl-online-kefu/quickstart.md](specs/001-cl-online-kefu/quickstart.md)

Includes reverse proxy samples for HTTP + WebSocket and release gate commands.

## 11. Troubleshooting

### Package QL does not exist

Use the unified runner [cl-fly/tests/run-tests.lisp](cl-fly/tests/run-tests.lisp). It auto-loads Quicklisp now.
If needed, set QUICKLISP_SETUP explicitly.

### Legacy port conflicts (8081/8082)

Use [cl-fly/cleanup-legacy-ports.ps1](cl-fly/cleanup-legacy-ports.ps1).

### Fast local restart

Use:

- [cl-fly/restart-server.ps1](cl-fly/restart-server.ps1)
- [cl-fly/restart-server.bat](cl-fly/restart-server.bat)

## 12. Security Notes

- Change bootstrap admin credentials before production use.
- Replace KEFU_JWT_SECRET with a strong secret.
- Keep upload/rate-limit policies enabled.
- Keep logs/audit enabled and avoid exposing sensitive values.

## 13. License

MIT (declared in [cl-fly/cl-fly.asd](cl-fly/cl-fly.asd)).

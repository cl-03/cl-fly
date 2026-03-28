# cl-fly

Common Lisp online customer service backend (Web + WebSocket), inspired by go-fly style workflows and adapted for spec-driven delivery.

## 1. Project Overview

`cl-fly` is a multi-role customer support backend that supports:

- Visitor session initialization and real-time messaging
- Agent auth, takeover, transfer, and queue/inbox views
- Runtime config management and blacklist controls
- Attachment upload/send flow with policy checks
- Typing/presence snapshots for better chat UX
- Contract/integration/perf gate tests for release confidence

## 2. Core Features

### Visitor / Session

- Session init (`queued -> active -> closed`)
- Message send with dedup (`sessionId + clientMsgId`)
- Replay/recent message retrieval
- Presence and typing snapshots

### Agent

- JWT login and password change
- Session accept and transfer
- Agent inbox with analytics sections
- Quick replies, macros, session attributes

### Admin / Operations

- Runtime config read/write
- Blacklist add/check flow
- Stats overview endpoint
- Default admin bootstrap (`admin/admin123`, forced change flow supported)

### Reliability / Security

- Rate limiting (auth/messages/upload)
- Input validation for payload length/type
- Upload policy checks (type/size)
- Security/audit logging hooks

## 3. Tech Stack

- Language: Common Lisp (SBCL)
- Web: Hunchentoot
- JSON: Jonathan
- DB: PostgreSQL (via Postmodern)
- Socket: usocket + custom WS server module
- Concurrency: bordeaux-threads
- Tests: FiveAM
- Dependency bootstrap: Quicklisp

ASD definition: [cl-fly/cl-fly.asd](cl-fly/cl-fly.asd)

## 4. Repository Layout

```text
cl-fly/
├── src/
│   ├── api/            # HTTP routes + WS handlers
│   ├── auth/           # JWT, RBAC
│   ├── core/           # domain services
│   ├── infra/          # config/db/logging/storage/ws server
│   ├── package.lisp
│   └── app.lisp
├── migrations/         # SQL migration files
├── static/site/        # demo pages (visitor/agent)
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
- Quicklisp installed
- PostgreSQL 15+ (recommended)

## 6. Environment Variables

Defined in [cl-fly/src/infra/config.lisp](cl-fly/src/infra/config.lisp).

| Variable | Default | Description |
|---|---|---|
| `KEFU_HTTP_PORT` | `4000` | HTTP port |
| `KEFU_WS_PORT` | `4001` | WebSocket port |
| `KEFU_DB_DSN` | `postgres://localhost:5432/cl_kefu` | PostgreSQL DSN |
| `KEFU_JWT_SECRET` | `dev-only-secret` | JWT signing secret |
| `KEFU_ENV` | `development` | Runtime environment |
| `KEFU_FILE_STORE` | `./uploads` | Upload storage directory |
| `KEFU_ADMIN_USERNAME` | `admin` | Bootstrap admin username |
| `KEFU_ADMIN_PASSWORD` | `admin123` | Bootstrap admin password |
| `QUICKLISP_SETUP` | _(none)_ | Optional quicklisp setup path override |
| `KEFU_ENABLE_RELEASE_GATES` | `0` | Enable release smoke gate in unified tests |
| `KEFU_ENABLE_PERF_BASELINE` | `0` | Enable SC-001 baseline sampling |

## 7. Quick Start

### 7.1 Database

Create DB (example):

```sql
CREATE DATABASE cl_kefu;
```

Run migration script:

```powershell
sbcl --load cl-fly/src/infra/migration.lisp --eval "(cl-fly.migration:up)" --quit
```

### 7.2 Start Server

#### Option A: Script entry (recommended)

```powershell
sbcl --script cl-fly/start-server.lisp
```

#### Option B: Load app module

```powershell
sbcl --load cl-fly/src/app.lisp --eval "(cl-fly.app:start)"
```

After startup:

- HTTP: `http://127.0.0.1:4000`
- Health: `GET /health`
- Visitor WS: `ws://127.0.0.1:4001/ws/visitor`
- Agent WS: `ws://127.0.0.1:4001/ws/agent`
- Demo pages:
  - `http://127.0.0.1:4000/chat`
  - `http://127.0.0.1:4000/agent-demo`

## 8. API and WS Contracts

### 8.1 Main HTTP Endpoints

Defined in [cl-fly/src/api/http-routes.lisp](cl-fly/src/api/http-routes.lisp).

- `GET /health`
- `GET/POST /api/v1/config`
- `POST /api/v1/blacklist`
- `GET /api/v1/blacklist/check`
- `GET /api/v1/stats/overview`
- `GET/POST /api/v1/sessions`
- `GET /api/v1/agent/inbox`
- `GET/POST /api/v1/messages`
- `GET /api/v1/sessions/presence`
- `GET /api/v1/sessions/typing`
- `POST /api/v1/files/upload`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/change-password`
- `GET/POST /api/v1/quick-reply-groups`
- `GET/POST /api/v1/quick-replies`
- `GET /api/v1/knowledge/snippets`
- `GET/POST /api/v1/macros`
- `GET/POST /api/v1/sessions/attributes`
- `GET/POST /api/v1/agents/presence`

### 8.2 WebSocket Contracts

Contract document: [specs/001-cl-online-kefu/contracts/websocket-events.md](specs/001-cl-online-kefu/contracts/websocket-events.md)

- Visitor endpoint: `/ws/visitor`
- Agent endpoint: `/ws/agent`
- Envelope fields: `event`, `requestId`, `timestamp`, `payload`
- Includes event definitions for `session.init`, `message.send`, `typing`, `session.transfer`, `ack`, `error`

## 9. Test and Quality Gates

Unified test entry: [cl-fly/tests/run-tests.lisp](cl-fly/tests/run-tests.lisp)

```powershell
sbcl --script cl-fly/tests/run-tests.lisp
```

The runner:

- Bootstraps Quicklisp dependencies automatically
- Executes contract/integration/unit suites
- Executes perf gates:
  - SC-001 (`tests/perf/perf_ws_200_concurrency.lisp`)
  - SC-002 (`tests/perf/perf_first_message_success_rate.lisp`)

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

- `cl-fly/tests/perf/reports/sc001-latest.txt`
- `cl-fly/tests/perf/reports/sc002-latest.txt`
- `cl-fly/tests/perf/reports/sc001-baseline-latest.txt` (when enabled)

## 10. Deployment (Nginx)

Deployment and smoke guidance is documented in:

- [specs/001-cl-online-kefu/quickstart.md](specs/001-cl-online-kefu/quickstart.md)

Includes:

- HTTP + WS reverse proxy sample
- `/health` and WS handshake acceptance checks
- Release gate command examples

## 11. Troubleshooting

### 11.1 `Package QL does not exist`

Use unified runner [cl-fly/tests/run-tests.lisp](cl-fly/tests/run-tests.lisp), which now auto-loads Quicklisp.
If needed, set `QUICKLISP_SETUP` explicitly.

### 11.2 Port conflict on 8081/8082 from legacy processes

Use cleanup helper:

- [cl-fly/cleanup-legacy-ports.ps1](cl-fly/cleanup-legacy-ports.ps1)

### 11.3 Fast local restart for development

Use restart helper:

- [cl-fly/restart-server.ps1](cl-fly/restart-server.ps1)
- [cl-fly/restart-server.bat](cl-fly/restart-server.bat)

## 12. Security Notes

- Change bootstrap admin credentials before production exposure.
- Replace `KEFU_JWT_SECRET` with a strong secret.
- Keep upload policy and rate limits enabled.
- Keep logs/audit trails and avoid exposing sensitive runtime values.

## 13. License

`MIT` (as declared in [cl-fly/cl-fly.asd](cl-fly/cl-fly.asd)).

---

If you want, I can also generate:

- an English README variant
- a condensed "operator-only" runbook
- a PR-ready release checklist section

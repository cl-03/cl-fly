# Development Resume State

Last updated: 2026-03-29

## Git snapshot
- Branch: 001-cl-online-kefu
- Last pushed commit: 88020b744f3675d188104be8c450742b77b5c6ed
- Commit subject: harden http actor attribution and add upload audit integration test

## What was just completed
- HTTP agent actor attribution is bound to JWT claims sub in message/upload paths.
- HTTP message send now writes audit events with actor aligned to authenticated identity.
- Added unit coverage for auth subject extraction and uploader identity preference.
- Added integration coverage to assert upload audit actor comes from token sub, not request uploaderId.
- Full test suite passed after these changes.

## Current local workspace state
There are additional local changes and untracked files in this repository not included in the last pushed commit.

Key modified tracked files:
- src/core/attachment.lisp
- src/core/blacklist.lisp
- src/core/bootstrap-admin.lisp
- src/core/config.lisp
- src/core/session.lisp
- src/infra/ws-server.lisp
- tests/integration/test_blacklist_flow.lisp
- tests/run-tests.lisp

## Suggested next loop
1. Continue HTTP/WS audit field consistency review (actor/action/target/details schema).
2. Add one more integration assertion for audit details payload shape consistency.
3. Run full regression:
   - sbcl --script tests/run-tests.lisp
4. Commit in small scoped batches to avoid mixing unrelated local changes.

## Fast restart commands
From workspace root:
- cd cl-fly
- git status --short
- git log -1 --oneline
- sbcl --script tests/run-tests.lisp

Or run the helper script:
- .\cl-fly\quick-resume.ps1
- .\cl-fly\quick-resume.ps1 -RunTests

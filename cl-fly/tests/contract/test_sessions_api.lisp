(defpackage #:cl-fly.tests.contract.sessions
  (:use #:cl #:fiveam)
  (:export #:run-sessions-contract-tests))

(in-package #:cl-fly.tests.contract.sessions)

(def-suite sessions-contract-suite
  :description "Contract checks for session APIs based on OpenAPI spec.")

(in-suite sessions-contract-suite)

(defun %read-openapi ()
  (uiop:read-file-string
   #p"d:/VSCode/project/specs/001-cl-online-kefu/contracts/openapi.yaml"))

(defun %read-http-routes ()
  (uiop:read-file-string
   #p"d:/VSCode/project/cl-fly/src/api/http-routes.lisp"))

(test sessions-create-endpoint-exists
  (let ((spec (%read-openapi)))
    (is-true (search "/api/v1/sessions:" spec))
    (is-true (search "post:" spec))
    (is-true (search "'201':" spec))))

(test sessions-transfer-endpoint-exists
  (let ((spec (%read-openapi)))
    (is-true (search "/api/v1/sessions/{sessionId}/transfer:" spec))
    (is-true (search "toAgentId" spec))
    (is-true (search "'409':" spec))))

(test agent-inbox-includes-analytics-shape
  (let ((src (%read-http-routes)))
    (is-true (search "/api/v1/agent/inbox" src))
    (is-true (search ":analytics" src))
    (is-true (search ":routingDashboard" src))
    (is-true (search ":touchesDashboard" src))
    (is-true (search ":currentAgent" src))
    (is-true (search ":myHandoff" src))
    (is-true (search ":myTouches" src))))

(test session-presence-requires-session-id
  (let ((src (%read-http-routes)))
    (is-true (search "/api/v1/sessions/presence" src))
    (is-true (search "sessionId is required" src))
    (is-true (search "INVALID_ARGUMENT" src))))

(defun run-sessions-contract-tests ()
  (run! 'sessions-contract-suite))

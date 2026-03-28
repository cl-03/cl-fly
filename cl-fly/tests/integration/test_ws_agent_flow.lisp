(defpackage #:cl-fly.tests.integration.ws-agent
  (:use #:cl #:fiveam)
  (:import-from #:cl-fly.auth.jwt
                #:issue-token
                #:verify-token)
  (:import-from #:cl-fly.auth.rbac
                #:allowed-p
                #:require-role)
  (:export #:run-ws-agent-integration-tests))

(in-package #:cl-fly.tests.integration.ws-agent)

(def-suite ws-agent-integration-suite
  :description "Agent-side websocket flow baseline checks.")

(in-suite ws-agent-integration-suite)

(test agent-jwt-roundtrip
  (let* ((token (issue-token "agent-1" :ttl-seconds 60 :role "agent"))
         (claims (verify-token token)))
    (is-true claims)
    (is (string= "agent-1" (getf claims :sub)))
    (is (string= "agent" (getf claims :role)))))

(test agent-rbac-checks
  (is-true (allowed-p "agent" "session:read"))
  (is-false (allowed-p "visitor" "settings:write"))
  (is-true (require-role "admin" "settings:write"))
  (signals error (require-role "visitor" "settings:write")))

(defun run-ws-agent-integration-tests ()
  (run! 'ws-agent-integration-suite))

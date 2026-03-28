(defpackage #:cl-fly.tests.contract.session-transfer
  (:use #:cl #:fiveam)
  (:export #:run-session-transfer-contract-tests))

(in-package #:cl-fly.tests.contract.session-transfer)

(def-suite session-transfer-contract-suite
  :description "Contract and behavior checks for session transfer.")

(in-suite session-transfer-contract-suite)

(defun %read-openapi ()
  (uiop:read-file-string
   #p"d:/VSCode/project/specs/001-cl-online-kefu/contracts/openapi.yaml"))

(test session-transfer-endpoint-contract
  (let ((spec (%read-openapi)))
    (is-true (search "/api/v1/sessions/{sessionId}/transfer:" spec))
    (is-true (search "toAgentId" spec))
    (is-true (search "'200':" spec))
    (is-true (search "'409':" spec))))

(test session-transfer-runtime-behavior
  (let* ((session (cl-fly.core.session:ensure-session "transfer-c-1"))
         (_ (cl-fly.core.session:accept-session "transfer-c-1" "agent-a"))
         (moved (cl-fly.core.session:transfer-session "transfer-c-1" "agent-b")))
    (declare (ignore session _))
    (is (string= "active" (getf moved :status)))
    (is (string= "agent-b" (getf moved :assignee)))
    (is (string= "agent-b" (cl-fly.core.session:session-assignee "transfer-c-1")))))

(defun run-session-transfer-contract-tests ()
  (run! 'session-transfer-contract-suite))

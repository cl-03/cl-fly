(defpackage #:cl-fly.tests.integration.transfer-flow
  (:use #:cl #:fiveam)
  (:export #:run-transfer-flow-integration-tests))

(in-package #:cl-fly.tests.integration.transfer-flow)

(def-suite transfer-flow-integration-suite
  :description "Integration checks for multi-agent transfer via WS handlers.")

(in-suite transfer-flow-integration-suite)

(test multi-agent-transfer-should-keep-session-active
  (let* ((session-id "transfer-i-1")
         (agent-b-token (cl-fly.auth.jwt:issue-token "agent-b" :ttl-seconds 60 :role "agent"))
         (visitor-init (cl-fly.api.ws-visitor:handle-visitor-event
                        "visitor-transfer-1"
                        "session.init"
                        (list :sessionId session-id)))
         (auth-b (cl-fly.api.ws-agent:handle-agent-event
                  "agent-transfer-b"
                  "agent.auth"
                  (list :token agent-b-token)))
         (accept-a (cl-fly.api.ws-agent:handle-agent-event
                    "agent-transfer-a"
                    "session.accept"
                    (list :sessionId session-id :agentId "agent-a")))
         (transfer-b (cl-fly.api.ws-agent:handle-agent-event
                      "agent-transfer-a"
                      "session.transfer"
                      (list :sessionId session-id :toAgentId "agent-b"))))
    (is (string= "session.ready" (getf visitor-init :event)))
    (is (string= "ack" (getf auth-b :event)))
    (is (string= "session.ready" (getf accept-a :event)))
    (is (string= "session.transferred" (getf transfer-b :event)))
    (is (string= "agent-b" (getf (getf transfer-b :payload) :toAgentId)))
    (is (string= "active" (cl-fly.core.session:session-status session-id)))))

(defun run-transfer-flow-integration-tests ()
  (run! 'transfer-flow-integration-suite))

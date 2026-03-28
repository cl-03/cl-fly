(defpackage #:cl-fly.tests.integration.ws-visitor
  (:use #:cl #:fiveam)
  (:import-from #:cl-fly.api.ws-visitor
                #:handle-visitor-event)
  (:import-from #:cl-fly.api.ws-common
                #:register-client
                #:touch-client
                #:unregister-client
                #:stale-clients)
  (:import-from #:cl-fly.core.session
                #:ensure-session)
  (:export #:run-ws-visitor-integration-tests))

(in-package #:cl-fly.tests.integration.ws-visitor)

(def-suite ws-visitor-integration-suite
  :description "Visitor-side websocket flow baseline checks.")

(in-suite ws-visitor-integration-suite)

(test visitor-register-touch-unregister
  (register-client "visitor-1" :role "visitor")
  (let ((entry (touch-client "visitor-1")))
    (is-true entry)
    (is (string= "visitor" (getf entry :role))))
  (unregister-client "visitor-1")
  (is-false (touch-client "visitor-1")))

(test visitor-stale-detection
  (register-client "visitor-stale" :role "visitor")
  (is-true (member "visitor-stale" (stale-clients :idle-seconds -1) :test #'string=))
  (unregister-client "visitor-stale"))

(test visitor-session-init-persists-prechat
  (let* ((res (handle-visitor-event
               "visitor-prechat-1"
               "session.init"
               (list :prechat (list :issueType "billing"
                                    :urgency "high"
                                    :language "zh-CN"
                                    :customerTier "enterprise"))))
         (payload (getf res :payload))
         (sid (getf payload :sessionId))
         (session (ensure-session sid)))
    (is (string= "session.ready" (getf res :event)))
    (is (string= "billing" (getf session :issue-type)))
    (is (string= "high" (getf session :urgency)))
    (is (string= "enterprise" (getf session :customer-tier)))
    (is-true (>= (or (getf session :intent-score) 0) 60))))

(test visitor-message-send-requires-session-id
  (let* ((res (handle-visitor-event
               "visitor-missing-session-1"
               "message.send"
               (list :messageType "text" :content "hello" :clientMsgId "ws-v-missing-sid")))
         (payload (getf res :payload)))
    (is (string= "error" (getf res :event)))
    (is (string= "INVALID_ARGUMENT" (getf payload :code)))))

(test visitor-replay-requires-session-id
  (let* ((res (handle-visitor-event
               "visitor-missing-session-2"
               "session.replay"
               (list)))
         (payload (getf res :payload)))
    (is (string= "error" (getf res :event)))
    (is (string= "INVALID_ARGUMENT" (getf payload :code)))))

(defun run-ws-visitor-integration-tests ()
  (run! 'ws-visitor-integration-suite))

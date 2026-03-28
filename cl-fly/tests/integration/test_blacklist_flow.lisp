(defpackage #:cl-fly.tests.integration.blacklist-flow
  (:use #:cl #:fiveam)
  (:export #:run-blacklist-flow-integration-tests))

(in-package #:cl-fly.tests.integration.blacklist-flow)

(defparameter *blocked-visitors* (make-hash-table :test 'equal))

(defun %block-visitor (visitor-id)
  (setf (gethash visitor-id *blocked-visitors*) t))

(defun %unblock-visitor (visitor-id)
  (remhash visitor-id *blocked-visitors*))

(defun %blocked-p (visitor-id)
  (and (gethash visitor-id *blocked-visitors*) t))

(defun %guarded-visitor-event (visitor-id event payload)
  (if (%blocked-p visitor-id)
      (list :event "error"
            :payload (list :code "BLACKLIST_BLOCKED"
                           :message "visitor blocked by blacklist"))
      (cl-fly.api.ws-visitor:handle-visitor-event visitor-id event payload)))

(def-suite blacklist-flow-integration-suite
  :description "Integration checks for blacklist decision in visitor event flow.")

(in-suite blacklist-flow-integration-suite)

(test blocked-visitor-should-be-rejected
  (%block-visitor "blocked-v-1")
  (let ((res (%guarded-visitor-event "blocked-v-1" "session.init" (list :sessionId "bl-1"))))
    (is (string= "error" (getf res :event)))
    (is (string= "BLACKLIST_BLOCKED" (getf (getf res :payload) :code))))
  (%unblock-visitor "blocked-v-1"))

(test unblocked-visitor-should-init-session
  (let ((res (%guarded-visitor-event "open-v-1" "session.init" (list :sessionId "bl-2"))))
    (is (string= "session.ready" (getf res :event)))
    (is (string= "bl-2" (getf (getf res :payload) :sessionId)))))

(defun run-blacklist-flow-integration-tests ()
  (run! 'blacklist-flow-integration-suite))

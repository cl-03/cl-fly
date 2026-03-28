(defpackage #:cl-fly.tests.integration.attachment-message-flow
  (:use #:cl #:fiveam)
  (:export #:run-attachment-message-flow-integration-tests))

(in-package #:cl-fly.tests.integration.attachment-message-flow)

(def-suite attachment-message-flow-integration-suite
  :description "Integration checks for attachment upload and message publish flow.")

(in-suite attachment-message-flow-integration-suite)

(test upload-then-send-attachment-message
  (let* ((session-id "attach-i-1")
         (result (cl-fly.core.attachment:process-upload-and-send
                  session-id
                  "visitor"
                  "visitor-1"
                  "demo.txt"
                  "text/plain"
                  12
                  "hello-world"
                  :client-msg-id "c-attach-1"))
         (messages (cl-fly.core.message:recent-messages session-id :limit 20)))
    (is-true (getf result :ok))
    (is (string= "attachment.sent" (getf result :event)))
    (is (string= "file" (getf (car (last messages)) :message-type)))))

(defun run-attachment-message-flow-integration-tests ()
  (run! 'attachment-message-flow-integration-suite))

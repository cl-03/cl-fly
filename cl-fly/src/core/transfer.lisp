(defpackage #:cl-fly.core.transfer
  (:use #:cl)
  (:import-from #:cl-fly.core.session
                #:ensure-session
                #:transfer-session
                #:session-assignee)
  (:import-from #:cl-fly.core.routing
                #:agent-online-p
                #:accept-session-with-routing
                #:mark-transfer-load)
  (:import-from #:cl-fly.core.audit
                #:write-audit-event)
  (:export #:transfer-session-with-fallback))

(in-package #:cl-fly.core.transfer)

(defun transfer-session-with-fallback (session-id to-agent-id &key from-agent-id)
  "Transfer session to target agent; keep current assignee when target is offline."
  (let* ((session (ensure-session session-id))
         (current-assignee (or from-agent-id (session-assignee session-id))))
    (cond
      ((or (null to-agent-id) (string= to-agent-id ""))
       (list :ok nil
             :code "TRANSFER_INVALID_TARGET"
             :message "toAgentId is required"
             :session session))
      ((not (agent-online-p to-agent-id))
       (write-audit-event (or current-assignee "system")
                          "session-transfer-failed"
                          "session"
                          session-id
                          (format nil "target-offline:~a" to-agent-id))
       (list :ok nil
             :code "TRANSFER_TARGET_OFFLINE"
             :message "target agent is offline"
             :session session
             :fallbackAssignee current-assignee))
      (t
       (let ((updated (if (or (null current-assignee) (string= current-assignee ""))
                          (accept-session-with-routing session-id to-agent-id)
                          (transfer-session session-id to-agent-id))))
         (mark-transfer-load current-assignee to-agent-id)
         (write-audit-event (or current-assignee "system")
                            "session-transferred"
                            "session"
                            session-id
                            (format nil "to:~a" to-agent-id))
         (list :ok t
               :session updated
               :fromAgentId current-assignee
             :toAgentId to-agent-id))))))

(in-package #:cl-fly.api.ws-agent)

(defun %payload-value (payload key)
  (or (getf payload key)
      (getf payload (intern (string-upcase key) :keyword))
      (and (hash-table-p payload) (gethash key payload nil))))

(defun handle-agent-event (client-id event payload)
  (register-client client-id :role "agent")
  (touch-client client-id)
  (cond
    ((string= event "agent.auth")
     (let* ((token (or (%payload-value payload :token)
                       (%payload-value payload "token")
                       ""))
                                    (capacity (or (%payload-value payload :capacity)
                                                                              (%payload-value payload "capacity")
                                                                              5))
            (claims (verify-token token)))
       (if claims
           (progn
                                     (set-agent-capacity (getf claims :sub) capacity)
                                     (set-agent-online (getf claims :sub) :capacity capacity)
             (write-audit-event (getf claims :sub) "agent-ws-auth-success" "agent" (getf claims :sub) "ws-auth-ok")
             (list :event "ack" :payload (list :status "ok" :sub (getf claims :sub))))
           (progn
             (write-audit-event "anonymous" "agent-ws-auth-failed" "agent" client-id "invalid-token")
             (list :event "error"
                   :payload (list :code "AUTH_INVALID_TOKEN" :message "Invalid token"))))))
            ((string= event "agent.presence.update")
             (let* ((agent-id (or (%payload-value payload :agentId)
                                                                              (%payload-value payload "agentId")
                                                                              ""))
                                    (capacity (or (%payload-value payload :capacity)
                                                                              (%payload-value payload "capacity")
                                                                              5)))
                   (if (string= agent-id "")
                               (list :event "error" :payload (list :code "INVALID_ARGUMENT" :message "agentId is required"))
                               (progn
                                     (set-agent-capacity agent-id capacity)
                                     (list :event "ack" :payload (list :status "ok" :agentId agent-id :capacity capacity))))))
    ((string= event "session.accept")
     (let* ((session-id (or (%payload-value payload :sessionId)
                            (%payload-value payload "sessionId")))
            (agent-id (or (%payload-value payload :agentId)
                          (%payload-value payload "agentId")
                          "agent"))
            (sid (if session-id (string-trim '(#\Space #\Tab #\Newline #\Return) session-id) "")))
       (if (string= sid "")
           (list :event "error"
                 :payload (list :code "INVALID_ARGUMENT" :message "sessionId is required"))
           (let ((session (accept-session-with-routing sid agent-id :capacity 5)))
             (bind-client-session client-id sid)
             (touch-session-activity sid "agent")
             (list :event "session.ready"
                   :payload (list :sessionId sid
                                  :status (getf session :status)
                                  :assignee (getf session :assignee)))))))
    ((string= event "session.transfer")
     (let* ((session-id (or (%payload-value payload :sessionId)
                            (%payload-value payload "sessionId")))
            (from-agent-id (or (%payload-value payload :fromAgentId)
                               (%payload-value payload "fromAgentId")
                               (session-assignee session-id)
                               ""))
            (to-agent-id (or (%payload-value payload :toAgentId)
                             (%payload-value payload "toAgentId")))
            (result (transfer-session-with-fallback session-id to-agent-id :from-agent-id from-agent-id)))
       (if (getf result :ok)
           (let ((session (getf result :session)))
             (list :event "session.transferred"
                   :payload (list :sessionId session-id
                                  :fromAgentId (getf result :fromAgentId)
                                  :toAgentId (getf result :toAgentId)
                                  :status (getf session :status))))
           (list :event "error"
                 :payload (list :code (getf result :code)
                                :message (getf result :message)
                                :sessionId session-id
                                :fallbackAssignee (getf result :fallbackAssignee))))))
    ((string= event "message.send")
     (let* ((session-id (or (%payload-value payload :sessionId)
                            (%payload-value payload "sessionId")))
            (msg-type (or (%payload-value payload :messageType)
                          (%payload-value payload "messageType")
                          "text"))
            (content (or (%payload-value payload :content)
                         (%payload-value payload "content")
                         ""))
            (client-msg-id (or (%payload-value payload :clientMsgId)
                               (%payload-value payload "clientMsgId")
                               ""))
            (msg-type-lc (string-downcase (or msg-type "")))
            (sid (if session-id (string-trim '(#\Space #\Tab #\Newline #\Return) session-id) "")))
       (cond
         ((string= sid "")
          (list :event "error"
                :payload (list :code "INVALID_ARGUMENT"
                               :message "sessionId is required")))
         ((member msg-type-lc '("text" "image" "file" "internal_note") :test #'string=)
          (let ((saved (send-message sid "agent" msg-type-lc content :client-msg-id client-msg-id)))
            (touch-session-activity sid "agent")
            (set-session-typing sid "agent" "")
            (list :event "ack"
                  :payload (list :status "ok"
                                 :messageId (getf saved :message-id)
                                 :clientMsgId client-msg-id
                                 :mentions (or (getf saved :mentions) '())))))
         (t
          (list :event "error"
                :payload (list :code "INVALID_ARGUMENT"
                               :message "unsupported messageType"))))))
    ((string= event "typing")
     (let* ((session-id (or (%payload-value payload :sessionId)
                            (%payload-value payload "sessionId")))
            (content (or (%payload-value payload :content)
                         (%payload-value payload "content")
                         "")))
       (set-session-typing session-id "agent" content)
       (list :event "ack" :payload (list :status "ok" :typing t))))
    ((string= event "session.replay")
     (let* ((session-id (or (%payload-value payload :sessionId)
                            (%payload-value payload "sessionId")))
            (sid (if session-id (string-trim '(#\Space #\Tab #\Newline #\Return) session-id) "")))
       (if (string= sid "")
           (list :event "error"
                 :payload (list :code "INVALID_ARGUMENT" :message "sessionId is required"))
           (let ((recent (recent-messages sid :limit 20)))
             (list :event "session.replay"
                   :payload (list :sessionId sid :messages recent))))))
    (t
     (list :event "error"
           :payload (list :code "UNSUPPORTED_EVENT"
                          :message "Unsupported agent event")))))

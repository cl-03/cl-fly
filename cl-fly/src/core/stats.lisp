(in-package #:cl-fly.core.stats)

(defun %status-is (session value)
  (string= (string-downcase (or (getf session :status) "")) value))

(defun %sum-field (sessions key)
  (reduce #'+ sessions :key (lambda (s) (or (getf s key) 0)) :initial-value 0))

(defun overview-stats ()
  (let* ((online-agents (cl-fly.core.agent-presence:list-online-agents))
         (sessions (cl-fly.core.session:list-sessions))
         (session-total (length sessions))
         (message-total (cl-fly.core.message:message-count))
         (queued (count-if (lambda (s) (%status-is s "queued")) sessions))
         (active (count-if (lambda (s) (%status-is s "active")) sessions))
         (handoff-total (%sum-field sessions :handoff-count))
         (reopen-total (%sum-field sessions :reopen-count))
         (visitor-touches (%sum-field sessions :visitor-touch-count))
         (agent-touches (%sum-field sessions :agent-touch-count))
         (touch-total (+ visitor-touches agent-touches)))
    (list :sessionsTotal session-total
          :messagesTotal message-total
          :onlineAgentsTotal (length online-agents)
          :queuedSessions queued
          :activeSessions active
          :routingDashboard (list :handoffTotal handoff-total
                                  :reopenTotal reopen-total)
          :touchesDashboard (list :visitorTouches visitor-touches
                                  :agentTouches agent-touches
                                  :totalTouches touch-total))))

(defpackage #:cl-fly.core.routing
  (:use #:cl)
  (:import-from #:cl-fly.core.session
                #:ensure-session
                #:accept-session
                #:session-assignee)
  (:import-from #:cl-fly.core.agent-presence
                #:set-agent-online
                #:set-agent-offline
                #:agent-online-p
                #:set-agent-capacity
                #:agent-capacity
                #:agent-load
                #:bump-agent-load
                #:list-online-agents)
  (:export
   #:set-agent-online
   #:set-agent-offline
   #:set-agent-capacity
   #:list-online-agents
   #:agent-online-p
   #:accept-session-with-routing
   #:assign-session-to-best-agent
   #:mark-transfer-load))

(in-package #:cl-fly.core.routing)

(defun accept-session-with-routing (session-id agent-id &key (capacity 5))
  (set-agent-online agent-id :capacity capacity)
  (let* ((existing (ensure-session session-id))
         (previous (getf existing :assignee))
         (session (accept-session session-id agent-id)))
    (when (and previous (not (string= previous agent-id)))
      (bump-agent-load previous -1))
    (bump-agent-load agent-id 1)
    session))

(defun %available-online-agents ()
  (remove-if-not
   (lambda (entry)
     (< (getf entry :load 0) (getf entry :capacity 1)))
   (list-online-agents)))

(defun assign-session-to-best-agent (session-id)
  (let* ((candidates (%available-online-agents))
         (winner (car (sort candidates #'< :key (lambda (x) (getf x :load))))))
    (if (null winner)
        nil
        (let* ((agent-id (getf winner :agentId))
               (session (accept-session session-id agent-id)))
          (bump-agent-load agent-id 1)
          session))))

(defun mark-transfer-load (from-agent-id to-agent-id)
  (when (and from-agent-id (not (string= from-agent-id "")))
    (bump-agent-load from-agent-id -1))
  (when (and to-agent-id (not (string= to-agent-id "")))
    (set-agent-online to-agent-id :capacity (agent-capacity to-agent-id))
    (bump-agent-load to-agent-id 1))
  t)

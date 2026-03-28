(defpackage #:cl-fly.core.agent-presence
  (:use #:cl)
  (:export
   #:set-agent-online
   #:set-agent-offline
   #:agent-online-p
   #:set-agent-capacity
   #:agent-capacity
   #:agent-load
   #:bump-agent-load
   #:list-online-agents))

(in-package #:cl-fly.core.agent-presence)

(defparameter *presence* (make-hash-table :test 'equal))
(defparameter *capacity* (make-hash-table :test 'equal))
(defparameter *load* (make-hash-table :test 'equal))
(defparameter *presence-lock* (bt:make-lock "agent-presence-lock"))

(defun set-agent-online (agent-id &key (capacity 5))
  (bt:with-lock-held (*presence-lock*)
    (setf (gethash agent-id *presence*) t)
    (setf (gethash agent-id *capacity*) (max 1 capacity))
    (unless (gethash agent-id *load*)
      (setf (gethash agent-id *load*) 0))
    (list :agentId agent-id
          :online t
          :capacity (gethash agent-id *capacity*)
          :load (gethash agent-id *load*))))

(defun set-agent-offline (agent-id)
  (bt:with-lock-held (*presence-lock*)
    (setf (gethash agent-id *presence*) nil)
    (list :agentId agent-id :online nil)))

(defun agent-online-p (agent-id)
  (bt:with-lock-held (*presence-lock*)
    (and (gethash agent-id *presence*) t)))

(defun set-agent-capacity (agent-id capacity)
  (bt:with-lock-held (*presence-lock*)
    (setf (gethash agent-id *capacity*) (max 1 capacity))
    (gethash agent-id *capacity*)))

(defun agent-capacity (agent-id)
  (bt:with-lock-held (*presence-lock*)
    (gethash agent-id *capacity* 5)))

(defun agent-load (agent-id)
  (bt:with-lock-held (*presence-lock*)
    (gethash agent-id *load* 0)))

(defun bump-agent-load (agent-id delta)
  (bt:with-lock-held (*presence-lock*)
    (let ((next (+ (gethash agent-id *load* 0) delta)))
      (setf (gethash agent-id *load*) (max 0 next))
      (gethash agent-id *load*))))

(defun list-online-agents ()
  (bt:with-lock-held (*presence-lock*)
    (let ((items '()))
      (maphash
       (lambda (agent-id online)
         (when online
           (push (list :agentId agent-id
                       :online t
                       :capacity (gethash agent-id *capacity* 5)
                       :load (gethash agent-id *load* 0))
                 items)))
       *presence*)
      (nreverse items))))

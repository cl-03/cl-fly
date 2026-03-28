(defpackage #:cl-fly.api.ws-common
  (:use #:cl)
  (:import-from #:cl-fly.infra.logging
                #:log-client-disconnect)
  (:export
   #:register-client
   #:unregister-client
   #:touch-client
   #:stale-clients
   #:bind-client-session
   #:session-clients))

(in-package #:cl-fly.api.ws-common)

(defparameter *clients* (make-hash-table :test 'equal))
(defparameter *session-clients* (make-hash-table :test 'equal))
(defparameter *clients-lock* (bt:make-lock "ws-common-clients-lock"))

(defun register-client (client-id &key role)
  (bt:with-lock-held (*clients-lock*)
    (setf (gethash client-id *clients*)
          (list :client-id client-id
                :role role
                :last-seen (get-universal-time)))))

(defun unregister-client (client-id)
  (bt:with-lock-held (*clients-lock*)
    (log-client-disconnect client-id)
    (remhash client-id *clients*)))

(defun touch-client (client-id)
  (bt:with-lock-held (*clients-lock*)
    (let ((entry (gethash client-id *clients*)))
      (when entry
        (setf (getf entry :last-seen) (get-universal-time))
        (setf (gethash client-id *clients*) entry))
      entry)))

(defun stale-clients (&key (idle-seconds 60))
  (bt:with-lock-held (*clients-lock*)
    (let ((now (get-universal-time))
          (stale nil))
      (maphash
       (lambda (id entry)
         (when (> (- now (getf entry :last-seen 0)) idle-seconds)
           (push id stale)))
       *clients*)
      stale)))

(defun bind-client-session (client-id session-id)
  (bt:with-lock-held (*clients-lock*)
    (let ((clients (gethash session-id *session-clients*)))
      (unless (member client-id clients :test #'string=)
        (push client-id clients))
      (setf (gethash session-id *session-clients*) clients)
      clients)))

(defun session-clients (session-id)
  (bt:with-lock-held (*clients-lock*)
    (copy-list (gethash session-id *session-clients*))))

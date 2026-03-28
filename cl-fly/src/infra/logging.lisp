(defpackage #:cl-fly.infra.logging
  (:use #:cl)
  (:export
   #:mask-sensitive
   #:log-info
   #:log-warn
  #:log-error
  #:log-session-created
  #:log-message-sent
  #:log-client-disconnect
  #:log-upload-failed
  #:log-security-event))

(in-package #:cl-fly.infra.logging)

(defparameter *sensitive-keys*
  '("password" "oldpassword" "newpassword" "token" "authorization"
    "secret" "apikey" "api-key" "cookie" "set-cookie" "credential"
    "filecontent" "file-content"))

(defun %sensitive-key-p (key)
  (let ((k (string-downcase (princ-to-string key))))
    (some (lambda (s) (search s k)) *sensitive-keys*)))

(defun mask-sensitive (plist)
  "Mask sensitive key values in a plist for safe logging."
  (loop for (k v) on plist by #'cddr
        append (list k (if (%sensitive-key-p k) "***" v))))

(defun %log (level message &optional fields)
  (let ((safe-fields (if fields (mask-sensitive fields) nil)))
    (format t "[~a] ~a~@[ | ~s~]~%" level message safe-fields)))

(defun log-info (message &optional fields)
  (%log "INFO" message fields))

(defun log-warn (message &optional fields)
  (%log "WARN" message fields))

(defun log-error (message &optional fields)
  (%log "ERROR" message fields))

(defun log-session-created (session-id)
  (log-info "session created" (list :session-id session-id)))

(defun log-message-sent (session-id message-id sender)
  (log-info "message sent" (list :session-id session-id :message-id message-id :sender sender)))

(defun log-client-disconnect (client-id)
  (log-info "client disconnected" (list :client-id client-id)))

(defun log-upload-failed (session-id uploader-id reason)
  (log-warn "upload failed"
            (list :session-id session-id :uploader-id uploader-id :reason reason)))

(defun log-security-event (event-name fields)
  (log-warn event-name fields))

(in-package #:cl-fly.core.attachment)

(defparameter *attachments* (make-hash-table :test 'equal))
(defparameter *attachments-by-session* (make-hash-table :test 'equal))
(defparameter *attachment-lock* (bt:make-lock "attachment-lock"))

(defun %new-attachment-id ()
  (format nil "a-~d" (get-universal-time)))

(defun register-attachment (session-id uploader-id filename mime size path)
  (let ((session (cl-fly.core.session:ensure-session session-id)))
    (unless session
      (error "session unavailable"))
    (let ((entry (list :attachment-id (%new-attachment-id)
                       :session-id session-id
                       :uploader-id uploader-id
                       :filename filename
                       :mime mime
                       :size size
                       :path path
                       :created-at (get-universal-time))))
      (bt:with-lock-held (*attachment-lock*)
        (setf (gethash (getf entry :attachment-id) *attachments*) entry)
        (setf (gethash session-id *attachments-by-session*)
              (append (gethash session-id *attachments-by-session*) (list entry))))
      entry)))

(defun attachment-permitted-p (attachment sender-type uploader-id)
  (declare (ignore sender-type))
  (and attachment
       uploader-id
       (or (string= uploader-id (getf attachment :uploader-id))
           (string= uploader-id "admin"))))

(defun process-upload-and-send (session-id sender-type uploader-id filename mime size content &key client-msg-id)
  (declare (ignore mime))
  (let ((policy (cl-fly.infra.storage:validate-upload filename size)))
    (unless (getf policy :ok)
      (cl-fly.infra.logging:log-upload-failed session-id uploader-id (getf policy :code))
      (return-from process-upload-and-send policy)))
  (let ((stored-path nil))
    (handler-case
        (let* ((saved-path (setf stored-path (cl-fly.infra.storage:store-file-local session-id filename content)))
               (meta (register-attachment session-id uploader-id filename "application/octet-stream" size saved-path)))
          (unless (attachment-permitted-p meta sender-type uploader-id)
            (cl-fly.infra.logging:log-security-event "attachment.permission.denied"
                                                     (list :session-id session-id :uploader-id uploader-id))
            (error "permission denied"))
          (let ((message (cl-fly.core.message:send-attachment-message session-id sender-type meta :client-msg-id client-msg-id)))
            (cl-fly.core.audit:write-audit-event uploader-id
                                                "attachment.upload"
                                                "attachment"
                                                (getf meta :attachment-id)
                                                (jonathan:to-json meta))
            (list :ok t
                  :event "attachment.sent"
                  :attachmentId (getf meta :attachment-id)
                  :messageId (getf message :message-id)
                  :path saved-path)))
      (error (e)
        (when stored-path
          (cl-fly.infra.storage:delete-stored-file stored-path))
        (cl-fly.infra.logging:log-upload-failed session-id uploader-id "UPLOAD_ROLLBACK")
        (list :ok nil :code "UPLOAD_FAILED" :message (princ-to-string e))))))

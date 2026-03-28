(in-package #:cl-fly.core.message)

(defparameter *messages-by-session* (make-hash-table :test 'equal))
(defparameter *dedup-index* (make-hash-table :test 'equal))
(defparameter *message-store-lock* (bordeaux-threads:make-lock "message-store-lock"))

(defun %mention-char-p (ch)
  (or (alphanumericp ch)
      (char= ch #\_)
      (char= ch #\-)
      (char= ch #\.)))

(defun %extract-mentions (content)
  (let* ((text (if (stringp content) content (princ-to-string content)))
         (len (length text))
         (i 0)
         (result '())
         (seen (make-hash-table :test 'equal)))
    (labels ((push-mention (value)
               (when (and (> (length value) 0)
                          (<= (length value) 64)
                          (not (gethash value seen)))
                 (setf (gethash value seen) t)
                 (push value result))))
      (loop while (< i len) do
        (if (char= (char text i) #\@)
            (let ((start (1+ i))
                  (j (1+ i)))
              (loop while (and (< j len) (%mention-char-p (char text j))) do
                (incf j))
              (when (> j start)
                (push-mention (subseq text start j)))
              (setf i j))
            (incf i))))
    (nreverse result)))

(defun message-count ()
  (bordeaux-threads:with-lock-held (*message-store-lock*)
    (let ((total 0))
      (maphash (lambda (_ bucket)
                 (declare (ignore _))
                 (incf total (length bucket)))
               *messages-by-session*)
      total)))

(defun %next-message-id ()
  (format nil "m-~d" (get-universal-time)))

(defun %dedup-key (session-id client-msg-id)
  (format nil "~a::~a" session-id client-msg-id))

(defun send-message (session-id sender-type message-type content &key client-msg-id)
  (bordeaux-threads:with-lock-held (*message-store-lock*)
    (when (and client-msg-id (not (string= client-msg-id "")))
      (let ((existing (gethash (%dedup-key session-id client-msg-id) *dedup-index*)))
        (when existing
          (return-from send-message existing))))
    (let* ((mentions (if (and (string= (string-downcase (or message-type "")) "internal_note")
                  (string= (string-downcase (or sender-type "")) "agent"))
               (%extract-mentions content)
               nil))
         (entry (list :message-id (%next-message-id)
                        :session-id session-id
                        :sender-type sender-type
                        :message-type message-type
                        :content content
              :mentions mentions
                        :client-msg-id client-msg-id
                        :created-at (get-universal-time)))
           (bucket (gethash session-id *messages-by-session*)))
      (setf (gethash session-id *messages-by-session*) (append bucket (list entry)))
      (when (and client-msg-id (not (string= client-msg-id "")))
        (setf (gethash (%dedup-key session-id client-msg-id) *dedup-index*) entry))
      entry)))

(defun recent-messages (session-id &key (limit 20))
  (bordeaux-threads:with-lock-held (*message-store-lock*)
    (let* ((all (gethash session-id *messages-by-session*))
           (size (length all)))
      (if (<= size limit)
          (copy-list all)
          (subseq all (- size limit))))))

(defun send-attachment-message (session-id sender-type attachment &key client-msg-id)
  (let ((payload (jonathan:to-json
                  (list :attachmentId (getf attachment :attachment-id)
                        :name (getf attachment :filename)
                        :size (getf attachment :size)
                        :path (getf attachment :path)
                        :previewUrl (getf attachment :path)))))
    (send-message session-id sender-type "file" payload :client-msg-id client-msg-id)))

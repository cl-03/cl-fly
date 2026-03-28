(in-package #:cl-fly.core.macro)

(defparameter *macros* (make-hash-table :test 'equal))
(defparameter *macro-seq* 0)
(defparameter *macro-lock* (bt:make-lock "macro-store-lock"))
(defparameter *allowed-action-keys* '("settag" "setpriority" "assignto" "setstatus"))
(defparameter *allowed-priority-values* '("low" "normal" "high" "urgent"))
(defparameter *allowed-status-values* '("queued" "active" "closed" "snoozed"))

(defun %next-macro-id ()
  (incf *macro-seq*)
  (format nil "m-~d" *macro-seq*))

(defun %blank-string-p (value)
  (and (stringp value)
       (string= (string-trim '(#\Space #\Tab #\Newline #\Return) value) "")))

(defun %valid-action-key-p (key)
  (member (string-downcase (princ-to-string key)) *allowed-action-keys* :test #'string=))

(defun %valid-action-value-p (key value)
  (let ((k (string-downcase (princ-to-string key))))
    (cond
      ((or (null value) (not (stringp value)) (%blank-string-p value) (> (length value) 128)) nil)
      ((string= k "setpriority")
       (member (string-downcase value) *allowed-priority-values* :test #'string=))
      ((string= k "setstatus")
       (member (string-downcase value) *allowed-status-values* :test #'string=))
      (t t))))

(defun validate-macro-actions (actions)
  (cond
    ((null actions) (values t '() nil))
    ((not (listp actions)) (values nil nil "actions must be a plist list"))
    ((oddp (length actions)) (values nil nil "actions must be key/value pairs"))
    (t
     (let ((normalized '()))
       (loop for (k v) on actions by #'cddr do
         (unless (%valid-action-key-p k)
           (return-from validate-macro-actions (values nil nil "unsupported action key")))
         (unless (%valid-action-value-p k v)
           (return-from validate-macro-actions (values nil nil "invalid action value")))
         (setf (getf normalized (intern (string-upcase (princ-to-string k)) :keyword)) v))
       (values t normalized nil)))))

(defun create-macro (title reply-template &key actions)
  (multiple-value-bind (ok normalized reason) (validate-macro-actions actions)
    (unless ok
      (error "invalid macro actions: ~a" reason))
  (bt:with-lock-held (*macro-lock*)
    (let* ((id (%next-macro-id))
           (now (get-universal-time))
           (entry (list :macroId id
                        :title title
                        :replyTemplate reply-template
                        :actions normalized
                        :createdAt now
                        :updatedAt now)))
      (setf (gethash id *macros*) entry)
      entry))))

(defun list-macros ()
  (bt:with-lock-held (*macro-lock*)
    (let ((items '()))
      (maphash (lambda (_id entry)
                 (declare (ignore _id))
                 (push entry items))
               *macros*)
      (sort items #'< :key (lambda (x) (or (getf x :createdAt) 0))))))

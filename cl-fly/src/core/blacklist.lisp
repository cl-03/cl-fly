(in-package #:cl-fly.core.blacklist)

(defparameter *blacklist* (make-hash-table :test 'equal))
(defparameter *blacklist-lock* (bt:make-lock "blacklist-lock"))

(defun %entry-key (type value)
  (format nil "~(~a~)::~a" type value))

(defun add-blacklist-entry (type value &key (reason ""))
  (let ((entry (list :type (string-downcase (string type))
                     :value value
                     :reason reason
                     :created-at (get-universal-time))))
    (bt:with-lock-held (*blacklist-lock*)
      (setf (gethash (%entry-key type value) *blacklist*) entry)
      entry)))

(defun blacklisted-p (type value)
  (bt:with-lock-held (*blacklist-lock*)
    (and (gethash (%entry-key type value) *blacklist*) t)))

(defun all-blacklist-entries ()
  (bt:with-lock-held (*blacklist-lock*)
    (let ((items '()))
      (maphash (lambda (_ entry)
                 (declare (ignore _))
                 (push entry items))
               *blacklist*)
      (nreverse items))))

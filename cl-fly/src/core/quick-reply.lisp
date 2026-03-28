(defpackage #:cl-fly.core.quick-reply
  (:use #:cl)
  (:export
   #:create-quick-reply-group
   #:list-quick-reply-groups
   #:create-quick-reply
   #:list-quick-replies))

(in-package #:cl-fly.core.quick-reply)

(defparameter *groups* (make-hash-table :test 'equal))
(defparameter *items* (make-hash-table :test 'equal))
(defparameter *group-seq* 0)
(defparameter *reply-seq* 0)
(defparameter *quick-reply-lock* (bt:make-lock "quick-reply-lock"))

(defun %next-group-id ()
  (incf *group-seq*)
  (format nil "qg-~d" *group-seq*))

(defun %next-reply-id ()
  (incf *reply-seq*)
  (format nil "qr-~d" *reply-seq*))

(defun create-quick-reply-group (name)
  (bt:with-lock-held (*quick-reply-lock*)
    (let ((id (%next-group-id)))
      (setf (gethash id *groups*)
            (list :groupId id
                  :name name
                  :createdAt (get-universal-time)))
      (gethash id *groups*))))

(defun list-quick-reply-groups ()
  (bt:with-lock-held (*quick-reply-lock*)
    (let ((items '()))
      (maphash (lambda (_id group)
                 (declare (ignore _id))
                 (push group items))
               *groups*)
      (nreverse items))))

(defun create-quick-reply (group-id content)
  (bt:with-lock-held (*quick-reply-lock*)
    (unless (gethash group-id *groups*)
      (error "quick reply group not found: ~a" group-id))
    (let ((id (%next-reply-id)))
      (setf (gethash id *items*)
            (list :replyId id
                  :groupId group-id
                  :content content
                  :createdAt (get-universal-time)))
      (gethash id *items*))))

(defun list-quick-replies (&optional group-id)
  (bt:with-lock-held (*quick-reply-lock*)
    (let ((items '()))
      (maphash (lambda (_id reply)
                 (declare (ignore _id))
                 (when (or (null group-id) (string= group-id (getf reply :groupId)))
                   (push reply items)))
               *items*)
      (nreverse items))))

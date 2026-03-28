(defpackage #:cl-fly.auth.rbac
  (:use #:cl)
  (:export
   #:allowed-p
   #:require-role))

(in-package #:cl-fly.auth.rbac)

(defparameter *role-permissions*
  '(("admin" . ("session:read" "session:write" "settings:write" "stats:read"))
    ("agent" . ("session:read" "session:write" "stats:read"))
    ("visitor" . ("session:read"))))

(defun allowed-p (role permission)
  (let ((perms (cdr (assoc role *role-permissions* :test #'string=))))
    (and perms (member permission perms :test #'string=))))

(defun require-role (role permission)
  (unless (allowed-p role permission)
    (error "RBAC denied for role=~a permission=~a" role permission))
  t)

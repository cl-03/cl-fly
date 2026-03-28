(defpackage #:cl-fly.infra.db
  (:use #:cl)
  (:import-from #:cl-fly.config
                #:config-get)
  (:export
   #:init-db
   #:with-db
   #:db-ready-p
   #:db-healthcheck))

(in-package #:cl-fly.infra.db)

(defparameter *db-dsn* nil)
(defparameter *db-ready* nil)

(defun db-ready-p ()
  *db-ready*)

(defun init-db ()
  "Initialize database DSN and perform a lightweight connectivity check."
  (setf *db-dsn* (config-get :db-dsn))
  (handler-case
      (progn
        (postmodern:with-connection *db-dsn*
          (postmodern:query "select 1" :single))
        (setf *db-ready* t))
    (error ()
      (setf *db-ready* nil)))
  *db-ready*)

(defmacro with-db (() &body body)
  `(progn
     (unless *db-dsn*
       (setf *db-dsn* (config-get :db-dsn)))
     (postmodern:with-connection *db-dsn*
       ,@body)))

(defun db-healthcheck ()
  (handler-case
      (with-db ()
        (equal 1 (postmodern:query "select 1" :single)))
    (error () nil)))

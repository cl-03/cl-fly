(in-package #:cl-fly.core.config)

(defparameter *runtime-config* (make-hash-table :test 'equal))
(defparameter *runtime-config-lock* (bt:make-lock "runtime-config-lock"))

(defun %safe-int (value &optional (default 0))
  (handler-case
      (etypecase value
        (integer value)
        (string (parse-integer value :junk-allowed t)))
    (error () default)))

(defun %clamp-int (value min-val max-val)
  (max min-val (min max-val value)))

(defun %snapshot-config ()
  (list :welcomeMessage (gethash "welcomeMessage" *runtime-config*)
  :siteTitle (gethash "siteTitle" *runtime-config*)
  :presenceIdleSeconds (gethash "presenceIdleSeconds" *runtime-config*)))

(defun %seed-defaults ()
  (bt:with-lock-held (*runtime-config-lock*)
    (unless (gethash "welcomeMessage" *runtime-config*)
      (setf (gethash "welcomeMessage" *runtime-config*) "Hello, welcome to online support."))
    (unless (gethash "siteTitle" *runtime-config*)
      (setf (gethash "siteTitle" *runtime-config*) "cl-fly support"))
    (unless (gethash "presenceIdleSeconds" *runtime-config*)
      (let* ((from-env (or (uiop:getenv "KEFU_PRESENCE_IDLE_SECONDS") "30"))
             (parsed (%safe-int from-env 30)))
        (setf (gethash "presenceIdleSeconds" *runtime-config*) (%clamp-int parsed 5 600))))))

(%seed-defaults)

(defun runtime-config-get (key &optional default)
  (let ((normalized (string key)))
    (bt:with-lock-held (*runtime-config-lock*)
      (gethash normalized *runtime-config* default))))

(defun welcome-message ()
  (runtime-config-get "welcomeMessage" "Hello, welcome to online support."))

(defun get-runtime-config ()
  (bt:with-lock-held (*runtime-config-lock*)
    (%snapshot-config)))

(defun update-runtime-config (&key welcome-message site-title presence-idle-seconds)
  (bt:with-lock-held (*runtime-config-lock*)
    (when (and welcome-message (not (string= welcome-message "")))
      (setf (gethash "welcomeMessage" *runtime-config*) welcome-message))
    (when (and site-title (not (string= site-title "")))
      (setf (gethash "siteTitle" *runtime-config*) site-title))
    (when presence-idle-seconds
      (let ((parsed (%safe-int presence-idle-seconds 30)))
        (setf (gethash "presenceIdleSeconds" *runtime-config*) (%clamp-int parsed 5 600))))
    (%snapshot-config)))

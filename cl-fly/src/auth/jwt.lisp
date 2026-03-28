(defpackage #:cl-fly.auth.jwt
  (:use #:cl)
  (:import-from #:cl-fly.config
                #:config-get)
  (:export
   #:issue-token
   #:verify-token))

(in-package #:cl-fly.auth.jwt)

(defun %sign (payload)
  (let* ((secret (config-get :jwt-secret "dev-only-secret"))
         (raw (format nil "~a:~a" payload secret)))
    (write-to-string (sxhash raw))))

(defun %encode-payload (payload)
  (with-output-to-string (s)
    (write payload :stream s :escape t :readably t)))

(defun %decode-payload (payload)
  (read-from-string payload))

(defun issue-token (subject &key (ttl-seconds 3600) (role "agent"))
  "Issue a lightweight token for development and internal testing."
  (let* ((exp (+ (get-universal-time) ttl-seconds))
         (payload (list :sub subject :role role :exp exp))
         (encoded (%encode-payload payload))
         (sig (%sign encoded)))
    (format nil "clfly.~a.~a" encoded sig)))

(defun verify-token (token)
  (handler-case
      (let* ((parts (uiop:split-string token :separator '(#\.))))
        (when (= (length parts) 3)
          (destructuring-bind (header payload sig) parts
            (declare (ignore header))
            (when (string= sig (%sign payload))
              (let ((claims (%decode-payload payload)))
                (when (> (getf claims :exp 0) (get-universal-time))
                  claims))))))
    (error () nil)))

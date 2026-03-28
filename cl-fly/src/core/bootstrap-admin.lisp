(defpackage #:cl-fly.core.bootstrap-admin
  (:use #:cl)
  (:import-from #:cl-fly.config
                #:config-get)
  (:import-from #:cl-fly.infra.db
                #:with-db)
  (:import-from #:cl-fly.auth.jwt
                #:issue-token)
  (:import-from #:cl-fly.core.audit
                #:write-audit-event)
  (:import-from #:cl-fly.infra.logging
                #:log-info
                #:log-warn)
  (:export
   #:ensure-default-admin
    #:agent-login
   #:admin-login
   #:change-admin-password))

(in-package #:cl-fly.core.bootstrap-admin)

(defun %app-env ()
  (string-downcase (or (config-get :app-env "development") "development")))

(defun %production-p ()
  (member (%app-env) '("prod" "production") :test #'string=))

(defun %sha256-hex (value)
  (let* ((octets (babel:string-to-octets (or value "") :encoding :utf-8))
         (digest (ironclad:digest-sequence :sha256 octets)))
    (ironclad:byte-array-to-hex-string digest)))

(defun %agent-row (username)
  (with-db ()
    (postmodern:query
     "select id, username, role, password_hash, must_change_password from agents where username = $1 limit 1"
     username
     :single)))

(defun %admin-row (username)
  (with-db ()
    (postmodern:query
     "select id, username, role, password_hash, must_change_password from agents where username = $1 and role = 'admin' limit 1"
     username
     :single)))

(defun %admin-count ()
  (with-db ()
    (or (postmodern:query "select count(1) from agents where role = 'admin'" :single) 0)))

(defun %must-change-on-bootstrap-p (password)
  (or (%production-p) (string= password "admin123")))

(defun ensure-default-admin ()
  "Ensure default admin account exists. In production/default-password cases, force password rotation."
  (let* ((username (or (config-get :admin-username "admin") "admin"))
         (password (or (config-get :admin-password "admin123") "admin123")))
    (when (zerop (%admin-count))
      (let ((must-change (%must-change-on-bootstrap-p password)))
        (with-db ()
          (postmodern:execute
           "insert into agents (username, role, password_hash, must_change_password, created_at) values ($1, 'admin', $2, $3, now())"
           username (%sha256-hex password) must-change))
        (write-audit-event "system" "admin-bootstrap" "agent" username
                           (if must-change "default-admin-created-password-change-required"
                               "default-admin-created"))
        (log-info "default admin bootstrapped" (list :username username :must-change-password must-change))))
    t))

(defun agent-login (username password)
  (let ((row (%agent-row username)))
    (if (null row)
        (progn
          (write-audit-event "anonymous" "agent-login-failed" "agent" username "agent-not-found")
          (list :ok nil :code "AUTH_INVALID" :message "invalid username or password"))
        (destructuring-bind (id db-username role db-password-hash must-change-password) row
          (declare (ignore id))
          (if (string= (%sha256-hex password) db-password-hash)
              (let ((token (issue-token db-username :role role :ttl-seconds 3600)))
                (write-audit-event db-username "agent-login-success" "agent" db-username "login-ok")
                (list :ok t
                      :token token
                      :username db-username
                      :role role
                      :mustChangePassword (and (string= role "admin") must-change-password t)))
              (progn
                (write-audit-event db-username "agent-login-failed" "agent" db-username "bad-password")
                (list :ok nil :code "AUTH_INVALID" :message "invalid username or password")))))))

(defun admin-login (username password)
  (let ((result (agent-login username password)))
    (if (and (getf result :ok) (not (string= (getf result :role "") "admin")))
        (list :ok nil :code "AUTH_FORBIDDEN" :message "admin role required")
        result)))

(defun change-admin-password (username old-password new-password)
  (let ((row (%admin-row username)))
    (cond
      ((null row)
       (list :ok nil :code "AUTH_INVALID" :message "invalid username or password"))
      ((or (null new-password) (< (length new-password) 8))
       (list :ok nil :code "PASSWORD_WEAK" :message "new password must be at least 8 characters"))
      (t
       (destructuring-bind (id db-username db-password-hash must-change-password) row
         (declare (ignore id must-change-password))
         (if (not (string= (%sha256-hex old-password) db-password-hash))
             (list :ok nil :code "AUTH_INVALID" :message "invalid username or password")
             (progn
               (with-db ()
                 (postmodern:execute
                  "update agents set password_hash = $1, must_change_password = false where username = $2 and role = 'admin'"
                  (%sha256-hex new-password)
                  db-username))
               (write-audit-event db-username "admin-password-changed" "agent" db-username "password-rotation")
               (log-info "admin password rotated" (list :username db-username))
               (list :ok t :message "password changed"))))))))

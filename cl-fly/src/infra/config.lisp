(in-package #:cl-fly.config)

(defparameter *config* (make-hash-table :test 'equal))

(defun %put (key value)
  (setf (gethash key *config*) value))

(defun config-get (key &optional default)
  (gethash key *config* default))

(defun load-config ()
  "Load runtime configuration from environment variables."
  (%put :http-port (parse-integer (or (uiop:getenv "KEFU_HTTP_PORT") "4000") :junk-allowed t))
  (%put :ws-port (parse-integer (or (uiop:getenv "KEFU_WS_PORT") "4001") :junk-allowed t))
  (%put :jwt-secret (or (uiop:getenv "KEFU_JWT_SECRET") "dev-only-secret"))
  (%put :db-dsn (or (uiop:getenv "KEFU_DB_DSN") "postgres://localhost:5432/cl_kefu"))
  (%put :app-env (or (uiop:getenv "KEFU_ENV") "development"))
  (%put :file-store (or (uiop:getenv "KEFU_FILE_STORE") "./uploads"))
  ;; Bootstrap defaults for initial admin login. Override in production.
  (%put :admin-username (or (uiop:getenv "KEFU_ADMIN_USERNAME") "admin"))
  (%put :admin-password (or (uiop:getenv "KEFU_ADMIN_PASSWORD") "admin123"))
  *config*)

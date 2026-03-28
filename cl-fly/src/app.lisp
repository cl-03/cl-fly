(in-package #:cl-fly.app)

(defun start ()
  "Bootstrap application configuration and print startup status.
Server binding is intentionally kept minimal for setup phase."
  (load-config)
  (let ((port (config-get :http-port 4000))
        (ws-port (config-get :ws-port 4001)))
    (if (init-db)
      (progn
        (log-info "Database connectivity check passed")
        (ensure-default-admin))
        (log-warn "Database connectivity check failed; service will start in degraded mode"))
    (start-http-server)
    (start-ws-server)
    (log-info "cl-fly startup complete" (list :port port :ws-port ws-port :db-ready (db-ready-p)))
    (list :port port :ws-port ws-port :db-ready (db-ready-p))))

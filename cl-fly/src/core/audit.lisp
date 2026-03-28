(defpackage #:cl-fly.core.audit
  (:use #:cl)
  (:import-from #:cl-fly.infra.db
                #:with-db)
  (:export
   #:write-audit-event
   #:write-config-change-audit
   #:write-blacklist-audit))

(in-package #:cl-fly.core.audit)

(defun write-audit-event (actor action target-type target-id details)
  "Persist an audit event for security and operability traces."
  (handler-case
      (progn
        (with-db ()
          (postmodern:execute
           "insert into audit_logs (actor, action, target_type, target_id, details, created_at) values ($1, $2, $3, $4, $5, now())"
           actor action target-type target-id details))
        t)
    (error ()
      ;; Keep audit best-effort in local/dev flows so core business path does not fail hard.
      nil)))

(defun write-config-change-audit (actor details)
  (write-audit-event actor "config.update" "config" "runtime" details))

(defun write-blacklist-audit (actor details)
  (write-audit-event actor "blacklist.add" "blacklist" "entry" details))

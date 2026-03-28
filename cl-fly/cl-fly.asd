(asdf:defsystem "cl-fly"
  :description "Online customer support backend in Common Lisp"
  :author "cl-fly contributors"
  :license "MIT"
  :version "0.1.0"
  :depends-on (
    "hunchentoot"
    "jonathan"
    "local-time"
    "postmodern"
    "usocket"
    "bordeaux-threads"
    "ironclad"
    "cl-base64"
    "babel")
  :serial t
  :components
  ((:file "src/package")
   (:file "src/infra/config")
   (:file "src/infra/db")
   (:file "src/infra/migration")
   (:file "src/infra/logging")
  (:file "src/infra/storage")
  (:file "src/infra/ws-server")
   (:file "src/auth/jwt")
   (:file "src/auth/rbac")
   (:file "src/api/error-response")
   (:file "src/api/ws-common")
  (:file "src/core/session")
  (:file "src/core/config")
  (:file "src/core/blacklist")
  (:file "src/core/agent-presence")
  (:file "src/core/routing")
  (:file "src/core/audit")
  (:file "src/core/stats")
  (:file "src/core/transfer")
  (:file "src/core/quick-reply")
  (:file "src/core/macro")
  (:file "src/core/session-attributes")
  (:file "src/core/message")
  (:file "src/core/attachment")
   (:file "src/core/repository")
  (:file "src/core/bootstrap-admin")
  (:file "src/api/ws-visitor")
  (:file "src/api/ws-agent")
  (:file "src/api/http-routes")
   (:file "src/app")))

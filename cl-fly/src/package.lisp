(defpackage #:cl-fly.config
  (:use #:cl)
  (:export
   #:load-config
   #:config-get
   #:*config*))

(defpackage #:cl-fly.infra.db
  (:use #:cl)
  (:import-from #:cl-fly.config
                #:config-get)
  (:export
   #:init-db
   #:with-db
   #:db-ready-p
   #:db-healthcheck))

(defpackage #:cl-fly.migration
  (:use #:cl)
  (:import-from #:cl-fly.infra.db
                #:with-db)
  (:export #:up))

(defpackage #:cl-fly.infra.logging
  (:use #:cl)
  (:export
   #:mask-sensitive
   #:log-info
   #:log-warn
  #:log-error
  #:log-session-created
  #:log-message-sent
  #:log-client-disconnect
  #:log-upload-failed
  #:log-security-event))

(defpackage #:cl-fly.infra.storage
  (:use #:cl)
  (:export
   #:sanitize-filename
   #:allowed-file-type-p
   #:valid-file-size-p
   #:validate-upload
   #:store-file-local
   #:delete-stored-file))

(defpackage #:cl-fly.infra.ws-server
  (:use #:cl)
  (:import-from #:cl-fly.config
           #:config-get)
  (:import-from #:cl-fly.infra.logging
           #:log-info
           #:log-warn
           #:log-error)
  (:export
  #:start-ws-server
  #:stop-ws-server))

(defpackage #:cl-fly.auth.jwt
  (:use #:cl)
  (:import-from #:cl-fly.config
                #:config-get)
  (:export
   #:issue-token
   #:verify-token))

(defpackage #:cl-fly.auth.rbac
  (:use #:cl)
  (:export
   #:allowed-p
   #:require-role))

(defpackage #:cl-fly.api.error
  (:use #:cl)
  (:export
   #:http-error
   #:http-error-status
   #:http-error-code
   #:http-error-message
   #:make-http-error
   #:error->response))

(defpackage #:cl-fly.core.session
  (:use #:cl)
  (:export
   #:ensure-session
  #:session-count
  #:list-sessions
  #:touch-session-activity
  #:set-session-prechat
  #:session-intent-score
  #:session-prechat-snapshot
  #:set-session-typing
  #:session-presence-snapshot
  #:session-typing-snapshot
   #:accept-session
   #:transfer-session
   #:session-status
   #:session-assignee))

(defpackage #:cl-fly.core.config
  (:use #:cl)
  (:export
  #:get-runtime-config
  #:runtime-config-get
  #:update-runtime-config
  #:welcome-message))

(defpackage #:cl-fly.core.blacklist
  (:use #:cl)
  (:export
  #:add-blacklist-entry
  #:blacklisted-p
  #:all-blacklist-entries))

(defpackage #:cl-fly.core.agent-presence
  (:use #:cl)
  (:export
   #:set-agent-online
   #:set-agent-offline
   #:agent-online-p
   #:set-agent-capacity
   #:agent-capacity
   #:agent-load
   #:bump-agent-load
   #:list-online-agents))

(defpackage #:cl-fly.core.audit
  (:use #:cl)
  (:import-from #:cl-fly.infra.db
                #:with-db)
  (:export
   #:write-audit-event
   #:write-config-change-audit
   #:write-blacklist-audit))

(defpackage #:cl-fly.core.stats
  (:use #:cl)
  (:export #:overview-stats))

(defpackage #:cl-fly.core.routing
  (:use #:cl)
  (:import-from #:cl-fly.core.session
                #:ensure-session
                #:accept-session
                #:session-assignee)
  (:import-from #:cl-fly.core.agent-presence
                #:set-agent-online
                #:set-agent-offline
                #:agent-online-p
                #:set-agent-capacity
                #:agent-capacity
                #:agent-load
                #:bump-agent-load
                #:list-online-agents)
  (:export
   #:set-agent-online
   #:set-agent-offline
   #:set-agent-capacity
   #:list-online-agents
   #:agent-online-p
   #:accept-session-with-routing
   #:assign-session-to-best-agent
   #:mark-transfer-load))

(defpackage #:cl-fly.core.quick-reply
  (:use #:cl)
  (:export
   #:create-quick-reply-group
   #:list-quick-reply-groups
   #:create-quick-reply
   #:list-quick-replies))

(defpackage #:cl-fly.core.macro
  (:use #:cl)
  (:export
  #:validate-macro-actions
   #:create-macro
   #:list-macros))

(defpackage #:cl-fly.core.session-attributes
  (:use #:cl)
  (:export
  #:list-session-attributes
  #:find-session-attributes
   #:set-session-attributes
   #:get-session-attributes))

(defpackage #:cl-fly.core.transfer
  (:use #:cl)
  (:import-from #:cl-fly.core.session
                #:ensure-session
                #:transfer-session
                #:session-assignee)
  (:import-from #:cl-fly.core.routing
                #:agent-online-p
                #:accept-session-with-routing
                #:mark-transfer-load)
  (:import-from #:cl-fly.core.audit
                #:write-audit-event)
  (:export #:transfer-session-with-fallback))

(defpackage #:cl-fly.core.message
  (:use #:cl)
  (:export
   #:send-message
  #:recent-messages
  #:message-count
  #:send-attachment-message))

(defpackage #:cl-fly.core.attachment
  (:use #:cl)
  (:import-from #:cl-fly.infra.storage
                #:validate-upload
                #:store-file-local
                #:delete-stored-file)
  (:import-from #:cl-fly.infra.logging
                #:log-upload-failed
                #:log-security-event)
  (:import-from #:cl-fly.core.message
                #:send-attachment-message)
  (:import-from #:cl-fly.core.audit
                #:write-audit-event)
  (:export
   #:register-attachment
   #:attachment-permitted-p
   #:process-upload-and-send))

(defpackage #:cl-fly.api.http
  (:use #:cl)
  (:import-from #:cl-fly.config
                #:config-get)
  (:import-from #:cl-fly.infra.db
                #:db-healthcheck)
  (:import-from #:cl-fly.core.session
                #:ensure-session
                #:list-sessions
                #:touch-session-activity
                #:set-session-prechat
                #:session-presence-snapshot
                #:session-typing-snapshot)
  (:import-from #:cl-fly.core.config
                #:get-runtime-config
                #:update-runtime-config)
  (:import-from #:cl-fly.core.blacklist
                #:add-blacklist-entry
                #:blacklisted-p)
  (:import-from #:cl-fly.core.stats
                #:overview-stats)
  (:import-from #:cl-fly.core.routing
                #:set-agent-online
                #:set-agent-offline
                #:set-agent-capacity
                #:list-online-agents)
  (:import-from #:cl-fly.core.quick-reply
                #:create-quick-reply-group
                #:list-quick-reply-groups
                #:create-quick-reply
                #:list-quick-replies)
  (:import-from #:cl-fly.core.macro
                #:validate-macro-actions
                #:create-macro
                #:list-macros)
  (:import-from #:cl-fly.core.session-attributes
                #:list-session-attributes
                #:find-session-attributes
                #:set-session-attributes
                #:get-session-attributes)
  (:import-from #:cl-fly.core.message
                #:send-message
                #:recent-messages)
  (:import-from #:cl-fly.core.attachment
                #:process-upload-and-send)
  (:import-from #:cl-fly.infra.logging
                #:log-info
                #:log-session-created
                #:log-message-sent
                #:log-security-event)
  (:import-from #:cl-fly.core.audit
                #:write-config-change-audit
                #:write-blacklist-audit)
  (:export
   #:start-http-server
   #:stop-http-server))

(defpackage #:cl-fly.api.ws-common
  (:use #:cl)
  (:import-from #:cl-fly.infra.logging
                #:log-client-disconnect)
  (:export
   #:register-client
   #:unregister-client
   #:touch-client
   #:stale-clients
   #:bind-client-session
   #:session-clients))

(defpackage #:cl-fly.api.ws-visitor
  (:use #:cl)
  (:import-from #:cl-fly.api.ws-common
                #:register-client
                #:touch-client
                #:bind-client-session)
  (:import-from #:cl-fly.core.blacklist
                #:blacklisted-p)
  (:import-from #:cl-fly.core.session
                #:ensure-session
                #:session-status
                #:touch-session-activity
                #:set-session-prechat
                #:set-session-typing)
  (:import-from #:cl-fly.core.message
                #:send-message
                #:recent-messages)
  (:export #:handle-visitor-event))

(defpackage #:cl-fly.api.ws-agent
  (:use #:cl)
  (:import-from #:cl-fly.auth.jwt
                #:verify-token)
  (:import-from #:cl-fly.core.audit
                #:write-audit-event)
  (:import-from #:cl-fly.api.ws-common
                #:register-client
                #:touch-client
                #:bind-client-session)
  (:import-from #:cl-fly.core.routing
                #:set-agent-online
                #:set-agent-capacity
                #:accept-session-with-routing)
  (:import-from #:cl-fly.core.transfer
                #:transfer-session-with-fallback)
  (:import-from #:cl-fly.core.session
                #:session-assignee
                #:touch-session-activity
                #:set-session-typing)
  (:import-from #:cl-fly.core.message
                #:send-message
                #:recent-messages)
  (:export #:handle-agent-event))

(defpackage #:cl-fly.core.repository
  (:use #:cl)
  (:import-from #:cl-fly.infra.db
                #:with-db)
  (:export
   #:create-visitor
   #:create-agent
   #:create-session
   #:append-message
   #:list-session-messages))

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

(defpackage #:cl-fly.app
  (:use #:cl)
  (:import-from #:cl-fly.config
                #:load-config
                #:config-get)
  (:import-from #:cl-fly.infra.db
                #:init-db
                #:db-ready-p)
  (:import-from #:cl-fly.api.http
                #:start-http-server)
  (:import-from #:cl-fly.core.bootstrap-admin
                #:ensure-default-admin)
  (:import-from #:cl-fly.infra.ws-server
                #:start-ws-server)
  (:import-from #:cl-fly.infra.logging
                #:log-info
                #:log-warn)
  (:import-from #:cl-fly.api.error
                #:error->response)
  (:export #:start))

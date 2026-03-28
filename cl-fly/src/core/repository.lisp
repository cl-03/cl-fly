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

(in-package #:cl-fly.core.repository)

(defun create-visitor (name)
  (with-db ()
    (postmodern:query
     "insert into visitors (name, created_at) values ($1, now()) returning id"
     name
     :single)))

(defun create-agent (username role)
  (with-db ()
    (postmodern:query
     "insert into agents (username, role, created_at) values ($1, $2, now()) returning id"
     username role
     :single)))

(defun create-session (visitor-id status)
  (with-db ()
    (postmodern:query
     "insert into sessions (visitor_id, status, created_at) values ($1, $2, now()) returning id"
     visitor-id status
     :single)))

(defun append-message (session-id sender-role content &key client-msg-id)
  (with-db ()
    (postmodern:query
     "insert into messages (session_id, sender_role, content, client_msg_id, created_at) values ($1, $2, $3, $4, now()) returning id"
     session-id sender-role content client-msg-id
     :single)))

(defun list-session-messages (session-id &key (limit 50))
  (with-db ()
    (postmodern:query
     "select id, sender_role, content, created_at from messages where session_id = $1 order by id desc limit $2"
     session-id limit)))

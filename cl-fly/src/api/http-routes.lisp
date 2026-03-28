(defpackage #:cl-fly.api.http
  (:use #:cl)
  (:import-from #:cl-fly.config
                #:config-get)
  (:import-from #:cl-fly.infra.db
                #:db-healthcheck)
  (:import-from #:cl-fly.core.bootstrap-admin
                #:agent-login
                #:change-admin-password)
  (:import-from #:cl-fly.auth.jwt
                #:verify-token)
  (:import-from #:cl-fly.core.session
                #:ensure-session
                #:set-session-prechat
                #:touch-session-activity
                #:session-presence-snapshot
                #:session-typing-snapshot)
  (:import-from #:cl-fly.core.config
                #:get-runtime-config
                #:runtime-config-get
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
                #:write-audit-event
                #:write-config-change-audit
                #:write-blacklist-audit)
  (:export
   #:start-http-server
   #:stop-http-server))

(in-package #:cl-fly.api.http)

(defparameter *acceptor* nil)
(defparameter *rate-limit-lock* (bt:make-lock "http-rate-limit-lock"))
(defparameter *rate-limit-buckets* (make-hash-table :test 'equal))
(defparameter *rate-limit-window-sec* 60)
(defparameter *rate-limit-auth-max* 20)
(defparameter *rate-limit-message-max* 120)
(defparameter *rate-limit-upload-max* 30)

(defparameter *max-session-id-length* 128)
(defparameter *max-client-msg-id-length* 128)
(defparameter *max-message-content-length* 4000)
(defparameter *max-filename-length* 255)
(defparameter *max-mime-type-length* 128)
(defparameter *max-actor-length* 64)
(defparameter *max-username-length* 64)
(defparameter *max-password-length* 128)
(defparameter *max-quick-reply-length* 2000)

(defun %json-response (payload &optional (status 200))
  (setf (hunchentoot:content-type*) "application/json")
  (setf (hunchentoot:return-code*) status)
  (jonathan:to-json payload))

(defun %request-json ()
  (let ((raw (hunchentoot:raw-post-data :force-text t)))
    (if (and raw (> (length raw) 0))
        (handler-case
            (jonathan:parse raw :as :plist)
          (error () nil))
        nil)))

(defun %json-get (plist key)
  (loop for (k v) on plist by #'cddr
        when (string-equal (string key) (string k)) do (return v)))

(defun %safe-int (value &optional (default 0))
  (handler-case
      (let ((parsed
              (etypecase value
                (integer value)
                (string (parse-integer value :junk-allowed t)))))
        (if (integerp parsed) parsed default))
    (error () default)))

(defun %read-file-text (pathname)
  (with-open-file (in pathname :direction :input :element-type 'character)
    (let ((out (make-string-output-stream)))
      (loop for line = (read-line in nil nil)
            while line
            do (progn
                 (write-string line out)
                 (write-char #\Newline out)))
      (get-output-stream-string out))))

(defun %site-root-directory ()
  (or (ignore-errors (asdf:system-source-directory :cl-fly))
      (ignore-errors (asdf:system-source-directory "cl-fly"))
      *default-pathname-defaults*))

(defun %site-file-path (name)
  (let* ((root (%site-root-directory))
         (preferred (merge-pathnames
                     (make-pathname :directory '(:relative "static" "site") :name name :type "html")
                     root))
         (legacy (merge-pathnames
                  (make-pathname :directory '(:relative "cl-fly" "static" "site") :name name :type "html")
                  *default-pathname-defaults*)))
    (cond
      ((probe-file preferred) preferred)
      ((probe-file legacy) legacy)
      (t preferred))))

(defun %serve-site-page (name)
  (let ((path (%site-file-path name)))
    (if (probe-file path)
        (progn
          (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
          (setf (hunchentoot:return-code*) 200)
          (%read-file-text path))
        (%json-response
         (list :ok nil :error (list :code "NOT_FOUND" :message "site page not found"))
         404))))

(defun %non-empty-string-p (value)
  (and (stringp value)
       (> (length (string-trim '(#\Space #\Tab #\Newline #\Return) value)) 0)))

(defun %bearer-token-from-header (&optional auth-header)
  (let* ((header (or auth-header (hunchentoot:header-in* "authorization")))
         (prefix "Bearer "))
    (when (and (stringp header)
               (>= (length header) (length prefix))
               (string-equal prefix (subseq header 0 (length prefix))))
      (let ((token (string-trim '(#\Space #\Tab #\Newline #\Return)
                                (subseq header (length prefix)))))
        (unless (string= token "")
          token)))))

(defun %agent-request-authorized-p (&optional auth-header)
  (not (null (%agent-auth-sub auth-header))))

(defun %agent-auth-sub (&optional auth-header)
  (let ((token (%bearer-token-from-header auth-header)))
    (when token
      (let ((claims (verify-token token)))
        (and claims
             (member (string-downcase (or (getf claims :role) ""))
                     '("agent" "admin")
                     :test #'string=)
             (%trimmed-string-or (getf claims :sub) nil))))))

(defun %trimmed-string-or (value fallback)
  (if (stringp value)
      (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) value)))
        (if (string= trimmed "") fallback trimmed))
      fallback))

(defun %effective-uploader-id (sender-type uploader-id &optional agent-sub)
  (if (string= (string-downcase (or sender-type "")) "visitor")
      "visitor"
      (%trimmed-string-or agent-sub (%trimmed-string-or uploader-id "agent"))))

(defun %string-length<= (value max-len)
  (or (null value)
      (not (stringp value))
      (<= (length value) max-len)))

(defun %allowed-string-p (value allowed)
  (and (stringp value)
       (member (string-downcase value) allowed :test #'string=)))

(defun %path-traversal-name-p (filename)
  (or (search ".." filename)
      (search "/" filename)
      (search "\\" filename)))

(defun %client-ip ()
  (or (hunchentoot:header-in* "x-forwarded-for")
      (handler-case (hunchentoot:remote-addr*) (error () nil))
      "unknown"))

(defun %rate-limit-ok-p (scope max-requests &optional (window-sec *rate-limit-window-sec*))
  (let* ((now (get-universal-time))
         (ip (%client-ip))
         (bucket-key (format nil "~a::~a" scope ip)))
    (bt:with-lock-held (*rate-limit-lock*)
      (let* ((bucket (remove-if (lambda (ts) (> (- now ts) window-sec))
                                (gethash bucket-key *rate-limit-buckets*)))
             (count (length bucket)))
        (if (< count max-requests)
            (progn
              (setf (gethash bucket-key *rate-limit-buckets*) (cons now bucket))
              (values t 0 ip))
            (let* ((oldest (if bucket (reduce #'min bucket) now))
                   (retry-after (max 1 (- window-sec (- now oldest)))))
              (values nil retry-after ip)))))))

(defun %rate-limit-response (scope max-requests)
  (multiple-value-bind (ok retry-after ip) (%rate-limit-ok-p scope max-requests)
    (if ok
        nil
        (progn
          (log-security-event
           "http_rate_limited"
           (list :scope scope :client-ip ip :retry-after retry-after :max-requests max-requests))
          (%json-response
           (list :ok nil
                 :error (list :code "RATE_LIMITED"
                              :message "too many requests"
                              :retryAfter retry-after))
           429)))))

(defun %message-field (item &rest keys)
  (loop for key in keys
        for value = (getf item key :__missing__)
        unless (eq value :__missing__)
          do (return value)
        finally (return nil)))

(defun %normalize-message-item (item)
  (let* ((raw-content (%message-field item :content))
         (content (cond
                    ((null raw-content) "")
                    ((stringp raw-content) raw-content)
                    (t (jonathan:to-json raw-content))))
         (mentions (or (%message-field item :mentions :mentionList)
                       '())))
    (list :messageId (%message-field item :message-id :messageId)
          :clientMsgId (%message-field item :client-msg-id :clientMsgId)
          :sessionId (%message-field item :session-id :sessionId)
          :senderType (or (%message-field item :sender-type :senderType) "visitor")
          :messageType (or (%message-field item :message-type :messageType) "text")
          :content content
          :mentions mentions
          :createdAt (%message-field item :created-at :createdAt))))

(defun %session-inbox-item (session)
  (let* ((sid (getf session :session-id))
         (recent (recent-messages sid :limit 1))
         (latest (and recent (first recent)))
         (latest-normalized (and latest (%normalize-message-item latest)))
         (last-activity (or (getf session :last-activity-at) (getf session :created-at) 0))
         (intent-score (or (getf session :intent-score) 0))
         (prechat (list :issueType (or (getf session :issue-type) "")
                        :urgency (or (getf session :urgency) "normal")
                        :language (or (getf session :language) "")
                        :customerTier (or (getf session :customer-tier) "standard")))
         (sla (%session-sla-details session))
         (typing (session-typing-snapshot sid :idle-seconds 8)))
    (list :sessionId sid
          :status (or (getf session :status) "queued")
          :assignee (getf session :assignee)
          :intentScore intent-score
          :prechat prechat
          :lastActivityAt last-activity
          :lastActivityUnix (- last-activity 2208988800)
          :sla sla
          :typing typing
          :latestMessage latest-normalized)))

(defun %session-visible-in-inbox-p (session)
  (let* ((sid (getf session :session-id))
         (recent (and sid (recent-messages sid :limit 1)))
         (latest (and recent (first recent)))
         (assignee (or (getf session :assignee) ""))
         (status (or (getf session :status) "queued")))
    (or latest
        (and (%non-empty-string-p assignee) (string= status "active")))))

(defun %session-sla-details (session &optional (now (get-universal-time)))
  (let* ((first-reply-at (getf session :first-reply-at))
         (first-reply-due-at (getf session :first-reply-due-at))
         (next-reply-due-at (getf session :next-reply-due-at))
         (active-due-at (if first-reply-at next-reply-due-at first-reply-due-at))
         (remaining (and active-due-at (- active-due-at now)))
         (state (cond
                  ((or (null active-due-at) (<= active-due-at 0)) "healthy")
                  ((< remaining 0) "breached")
                  ((<= remaining 30) "at-risk")
                  (t "healthy"))))
    (list :state state
          :firstReplyAt first-reply-at
          :firstReplyAtUnix (and first-reply-at (- first-reply-at 2208988800))
          :firstReplyDueAt first-reply-due-at
          :firstReplyDueAtUnix (and first-reply-due-at (- first-reply-due-at 2208988800))
          :nextReplyDueAt next-reply-due-at
          :nextReplyDueAtUnix (and next-reply-due-at (- next-reply-due-at 2208988800))
          :activeDueAt active-due-at
          :activeDueAtUnix (and active-due-at (- active-due-at 2208988800))
          :remainingSec remaining)))

(defun %sla-summary (sessions)
  (let ((healthy 0)
        (at-risk 0)
        (breached 0))
    (dolist (session sessions)
      (let* ((sla (%session-sla-details session))
             (state (string-downcase (or (getf sla :state) "healthy"))))
        (cond
          ((string= state "breached") (incf breached))
          ((string= state "at-risk") (incf at-risk))
          (t (incf healthy)))))
    (list :healthy healthy :atRisk at-risk :breached breached)))

(defun %workload-summary (agent-id sessions)
  (let* ((agents (list-online-agents))
         (online-count (length agents))
         (total-load (reduce #'+ agents :key (lambda (x) (or (getf x :load) 0)) :initial-value 0))
         (total-capacity (reduce #'+ agents :key (lambda (x) (or (getf x :capacity) 0)) :initial-value 0))
         (mine (and (%non-empty-string-p agent-id)
                    (find agent-id agents :test #'string= :key (lambda (x) (getf x :agentId)))))
         (mine-load (or (and mine (getf mine :load)) 0))
         (mine-capacity (or (and mine (getf mine :capacity)) 0))
         (assigned-active
          (if (%non-empty-string-p agent-id)
              (count-if (lambda (s)
                          (and (string= (or (getf s :assignee) "") agent-id)
                               (string= (or (getf s :status) "") "active")))
                        sessions)
              0)))
    (list :onlineAgents online-count
          :totalLoad total-load
          :totalCapacity total-capacity
          :currentAgentId (or agent-id "")
          :currentLoad mine-load
          :currentCapacity mine-capacity
          :currentAssignedActive assigned-active
          :currentUtilizationPct (if (> mine-capacity 0)
                                     (round (* 100 (/ mine-load mine-capacity)))
                                     0))))

(defun %analytics-summary (sessions &key agent-id)
  (let ((handoff-total 0)
        (reopen-total 0)
        (visitor-touches 0)
        (agent-touches 0)
        (my-handoff 0)
        (my-touches 0)
        (my-active-sessions 0))
    (dolist (s sessions)
      (let* ((handoff (or (getf s :handoff-count) 0))
             (reopen (or (getf s :reopen-count) 0))
             (vt (or (getf s :visitor-touch-count) 0))
             (at (or (getf s :agent-touch-count) 0))
             (assignee (or (getf s :assignee) ""))
             (status (or (getf s :status) ""))
             (touch-counts (or (getf s :agent-touch-counts) '()))
             (handoff-counts (or (getf s :agent-handoff-counts) '()))
             (my-touch-on-session (or (cdr (assoc (or agent-id "") touch-counts :test #'string=)) 0))
             (my-handoff-on-session (or (cdr (assoc (or agent-id "") handoff-counts :test #'string=)) 0))
             (mine (and (%non-empty-string-p agent-id)
                        (string= assignee agent-id))))
        (incf handoff-total handoff)
        (incf reopen-total reopen)
        (incf visitor-touches vt)
        (incf agent-touches at)
        (incf my-handoff my-handoff-on-session)
        (incf my-touches my-touch-on-session)
        (when mine
          (when (string= status "active")
            (incf my-active-sessions)))))
    (list :routingDashboard (list :handoffTotal handoff-total
                                  :reopenTotal reopen-total)
          :touchesDashboard (list :visitorTouches visitor-touches
                                  :agentTouches agent-touches
                                  :totalTouches (+ visitor-touches agent-touches))
          :currentAgent (list :agentId (or agent-id "")
                              :myHandoff my-handoff
                              :myTouches my-touches
                              :myActiveSessions my-active-sessions))))

(defun %extract-session-attributes (data)
  (let ((nested (or (%json-get data :attributes)
                    (%json-get data :sessionAttributes)
                    (%json-get data :session-attributes))))
    (if (listp nested)
        nested
        (list :issueType (or (%json-get data :issueType) (%json-get data :issue-type))
              :urgency (or (%json-get data :urgency) (%json-get data :priority))
              :language (or (%json-get data :language) (%json-get data :lang))
              :customerTier (or (%json-get data :customerTier) (%json-get data :customer-tier))))))

(defun %extract-prechat (data)
  (let* ((nested (or (%json-get data :prechat)
                     (%json-get data :preChat)
                     (%json-get data :pre-chat)
                     (%json-get data :qualificationCard)))
         (source (if (listp nested) nested data)))
    (list :issueType (or (%json-get source :issueType)
                         (%json-get source :issue-type))
          :urgency (or (%json-get source :urgency)
                       (%json-get source :priority))
          :language (or (%json-get source :language)
                        (%json-get source :lang))
          :customerTier (or (%json-get source :customerTier)
                            (%json-get source :customer-tier))
          :intentScore (or (%json-get source :intentScore)
                           (%json-get source :intent-score)))))

(defun %string-contains-ci-p (haystack needle)
  (let ((h (string-downcase (or haystack "")))
        (n (string-downcase (or needle ""))))
    (and (> (length n) 0)
         (not (null (search n h :test #'char=))))))

(defun %query-tokens (query)
  (let ((q (string-trim '(#\Space #\Tab #\Newline #\Return) (or query "")))
        (tokens '())
        (current ""))
    (labels ((flush-current ()
               (when (> (length current) 0)
                 (push (string-downcase current) tokens)
                 (setf current ""))))
      (loop for ch across q do
        (if (member ch '(#\Space #\Tab #\Newline #\Return) :test #'char=)
            (flush-current)
            (setf current (concatenate 'string current (string ch)))))
      (flush-current))
    (nreverse tokens)))

(defun %snippet-match-score (content tokens)
  (if (null tokens)
      0
      (let ((score 0))
        (dolist (token tokens score)
          (if (%string-contains-ci-p content token)
              (incf score)
              (return-from %snippet-match-score nil))))))

(defun %group-name-map ()
  (let ((table (make-hash-table :test 'equal)))
    (dolist (group (list-quick-reply-groups))
      (setf (gethash (or (getf group :groupId) "") table)
            (or (getf group :name) "")))
    table))

(defun %knowledge-search-items (&key query group-id (limit 20))
  (let* ((tokens (%query-tokens query))
         (replies (if (%non-empty-string-p group-id)
                      (list-quick-replies group-id)
                      (list-quick-replies)))
         (group-map (%group-name-map))
         (matched '()))
    (dolist (reply replies)
      (let* ((content (or (getf reply :content) ""))
             (score (%snippet-match-score content tokens)))
        (when (or (null tokens) score)
          (push (list :snippetId (or (getf reply :replyId) "")
                      :groupId (or (getf reply :groupId) "")
                      :groupName (or (gethash (or (getf reply :groupId) "") group-map) "")
                      :content content
                      :createdAt (or (getf reply :createdAt) 0)
                      :score (or score 0))
                matched))))
    (let* ((sorted (sort matched
                         (lambda (a b)
                           (let ((sa (or (getf a :score) 0))
                                 (sb (or (getf b :score) 0))
                                 (ta (or (getf a :createdAt) 0))
                                 (tb (or (getf b :createdAt) 0)))
                             (if (/= sa sb)
                                 (> sa sb)
                                 (> ta tb))))))
           (safe-limit (max 1 (min 50 limit)))
           (total (length sorted)))
      (if (> total safe-limit)
          (subseq sorted 0 safe-limit)
          sorted))))

(hunchentoot:define-easy-handler (health-handler :uri "/health") ()
  (let ((db-ok (db-healthcheck)))
  (%json-response
   (list :ok t
         :db (if db-ok "up" "down")
         :dbReachable db-ok
         :service "cl-fly")
   200)))

(hunchentoot:define-easy-handler (favicon-handler :uri "/favicon.ico") ()
  ;; Suppress browser default favicon 404 noise for demo site routes.
  (setf (hunchentoot:return-code*) 204)
  (setf (hunchentoot:content-type*) "image/x-icon")
  "")

(hunchentoot:define-easy-handler (site-home-handler :uri "/") ()
  (%serve-site-page "index"))

(hunchentoot:define-easy-handler (site-service-handler :uri "/service") ()
  (%serve-site-page "service"))

(hunchentoot:define-easy-handler (site-chat-handler :uri "/chat") ()
  (%serve-site-page "chat"))

(hunchentoot:define-easy-handler (site-agent-demo-handler :uri "/agent-demo") ()
  (%serve-site-page "agent-demo"))

(hunchentoot:define-easy-handler (config-handler :uri "/api/v1/config") ()
  (cond
    ((eql (hunchentoot:request-method*) :get)
     (%json-response (list :ok t :config (get-runtime-config)) 200))
    ((eql (hunchentoot:request-method*) :put)
     (let* ((data (%request-json))
            (welcome-message (or (%json-get data :welcomeMessage)
                                 (%json-get data :welcome-message)
                                 nil))
            (site-title (or (%json-get data :siteTitle)
                            (%json-get data :site-title)
                            nil))
          (presence-idle-seconds (or (%json-get data :presenceIdleSeconds)
                      (%json-get data :presence-idle-seconds)
                      nil))
            (actor (or (%json-get data :actor) "admin"))
            (updated (update-runtime-config :welcome-message welcome-message
                        :site-title site-title
                        :presence-idle-seconds presence-idle-seconds)))
       (write-config-change-audit actor (jonathan:to-json updated))
       (%json-response (list :ok t :config updated) 200)))
    (t
     (%json-response (list :ok nil :error (list :code "METHOD_NOT_ALLOWED" :message "GET or PUT required")) 405))))

(hunchentoot:define-easy-handler (blacklist-handler :uri "/api/v1/blacklist") ()
  (if (eql (hunchentoot:request-method*) :post)
      (let* ((data (%request-json))
             (entry-type (or (%json-get data :type) ""))
             (value (or (%json-get data :value) ""))
             (reason (or (%json-get data :reason) ""))
             (actor (or (%json-get data :actor) "admin")))
        (cond
          ((or (not (%non-empty-string-p entry-type))
               (not (%non-empty-string-p value)))
           (log-security-event "blacklist_invalid_payload" (list :actor actor :type entry-type))
           (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "type and value are required")) 400))
          ((or (not (%allowed-string-p entry-type '("ip" "device" "fingerprint" "token")))
               (not (%string-length<= value 256))
               (not (%string-length<= reason 256))
               (not (%string-length<= actor *max-actor-length*)))
           (log-security-event "blacklist_validation_failed" (list :actor actor :type entry-type))
           (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "invalid blacklist payload")) 400))
          (t
           (let ((entry (add-blacklist-entry entry-type value :reason reason)))
             (write-blacklist-audit actor (jonathan:to-json entry))
             (%json-response (list :ok t :entry entry) 201)))))
      (%json-response (list :ok nil :error (list :code "METHOD_NOT_ALLOWED" :message "POST required")) 405)))

(hunchentoot:define-easy-handler (blacklist-check-handler :uri "/api/v1/blacklist/check") (type value)
  (if (eql (hunchentoot:request-method*) :get)
      (%json-response (list :ok t
                            :type type
                            :value value
                            :blocked (blacklisted-p type value))
                      200)
      (%json-response (list :ok nil :error (list :code "METHOD_NOT_ALLOWED" :message "GET required")) 405)))

(hunchentoot:define-easy-handler (stats-overview-handler :uri "/api/v1/stats/overview") ()
  (%json-response (list :ok t :overview (overview-stats)) 200))

(hunchentoot:define-easy-handler (sessions-handler :uri "/api/v1/sessions") ()
  (if (eql (hunchentoot:request-method*) :post)
      (let* ((data (%request-json))
             (incoming-id (or (%json-get data :sessionId)
                              (%json-get data :session-id)
                              nil))
             (session (ensure-session incoming-id))
             (sid (getf session :session-id))
             (prechat (%extract-prechat data))
             (updated (set-session-prechat sid
                                           :issue-type (getf prechat :issueType)
                                           :urgency (getf prechat :urgency)
                                           :language (getf prechat :language)
                                           :customer-tier (getf prechat :customerTier)
                                           :intent-score (getf prechat :intentScore))))
        (log-session-created (getf session :session-id))
        (%json-response (list :ok t
                              :sessionId sid
                              :status (getf updated :status)
                              :intentScore (or (getf updated :intent-score) 0)
                              :prechat (list :issueType (or (getf updated :issue-type) "")
                                             :urgency (or (getf updated :urgency) "normal")
                                             :language (or (getf updated :language) "")
                                             :customerTier (or (getf updated :customer-tier) "standard")))
                        201))
      (%json-response
       (list :ok t
         :items (mapcar (lambda (s)
              (list :sessionId (getf s :session-id)
                :status (getf s :status)
                :assignee (getf s :assignee)
                :intentScore (or (getf s :intent-score) 0)
                :prechat (list :issueType (or (getf s :issue-type) "")
                               :urgency (or (getf s :urgency) "normal")
                               :language (or (getf s :language) "")
                               :customerTier (or (getf s :customer-tier) "standard"))
                :lastActivityAt (getf s :last-activity-at)
                :lastActivityUnix (- (or (getf s :last-activity-at) 0) 2208988800)
                :sla (%session-sla-details s)))
                (list-sessions)))
       200)))

(hunchentoot:define-easy-handler (agent-inbox-handler :uri "/api/v1/agent/inbox") (agentId)
  (if (eql (hunchentoot:request-method*) :get)
  (let* ((sessions (remove-if-not #'%session-visible-in-inbox-p (list-sessions)))
             (aid (or agentId "")))
        (%json-response (list :ok t
                              :sessions (mapcar #'%session-inbox-item sessions)
                              :sla (%sla-summary sessions)
                :workload (%workload-summary aid sessions)
                :analytics (%analytics-summary sessions :agent-id aid))
                        200))
      (%json-response (list :ok nil :error (list :code "METHOD_NOT_ALLOWED" :message "GET required")) 405)))

(hunchentoot:define-easy-handler (messages-handler :uri "/api/v1/messages") (sessionId)
  (if (eql (hunchentoot:request-method*) :get)
      (let* ((limit (max 1 (min 200 (%safe-int (hunchentoot:parameter "limit") 20))))
             (viewer-type (string-downcase (or (hunchentoot:parameter "viewerType")
                                               (hunchentoot:parameter "viewer-type")
                                               "visitor")))
             (recent (recent-messages sessionId :limit limit))
             (visible (if (string= viewer-type "agent")
                          recent
                          (remove-if (lambda (item)
                                       (string= (string-downcase (or (%message-field item :message-type :messageType) "text"))
                                                "internal_note"))
                                     recent)))
             (normalized (mapcar #'%normalize-message-item visible)))
        (%json-response (list :ok t :sessionId sessionId :messages normalized) 200))
      (let* ((data (%request-json))
             (limit-resp (%rate-limit-response "messages.post" *rate-limit-message-max*))
             (session-id (or (%json-get data :sessionId)
                             (%json-get data :session-id)))
             (sender-type (or (%json-get data :senderType)
                              (%json-get data :sender-type)
                              "visitor"))
              (agent-sub (%agent-auth-sub))
             (msg-type (or (%json-get data :messageType)
                           (%json-get data :message-type)
                           "text"))
             (content (or (%json-get data :content) ""))
             (client-msg-id (or (%json-get data :clientMsgId)
                                (%json-get data :client-msg-id)
                                "")))
        (cond
          (limit-resp limit-resp)
          ((or (not (%non-empty-string-p session-id))
               (> (length session-id) *max-session-id-length*))
           (log-security-event "message_invalid_session" (list :session-id session-id))
           (%json-response (list :ok nil :error (list :code "SESSION_NOT_FOUND" :message "sessionId is required")) 400))
          ((not (%allowed-string-p msg-type '("text" "image" "file" "internal_note")))
           (log-security-event "message_invalid_type" (list :message-type msg-type :session-id session-id))
           (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "unsupported messageType")) 400))
            ((not (%allowed-string-p sender-type '("visitor" "agent")))
             (log-security-event "message_invalid_sender" (list :sender-type sender-type :session-id session-id))
             (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "unsupported senderType")) 400))
          ((and (string= (string-downcase msg-type) "internal_note")
             (not (string= (string-downcase sender-type) "agent")))
           (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "internal_note requires senderType=agent")) 400))
          ((and (string= (string-downcase sender-type) "agent")
             (null agent-sub))
           (log-security-event "message_agent_sender_unauthorized" (list :session-id session-id))
           (%json-response (list :ok nil :error (list :code "AUTH_FORBIDDEN" :message "agent sender requires bearer token")) 401))
          ((or (not (%non-empty-string-p content))
               (> (length content) *max-message-content-length*))
           (log-security-event "message_invalid_content" (list :session-id session-id :length (length content)))
           (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "content is required and must be <= 4000 chars")) 400))
          ((and (%non-empty-string-p client-msg-id)
                (> (length client-msg-id) *max-client-msg-id-length*))
           (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "clientMsgId is too long")) 400))
          (t
           (let ((saved (send-message session-id sender-type msg-type content :client-msg-id client-msg-id)))
             (touch-session-activity session-id sender-type)
             (log-message-sent session-id (getf saved :message-id) sender-type)
             (write-audit-event (if (string= (string-downcase sender-type) "agent")
                                    agent-sub
                                    "visitor")
                                "message.send.http"
                                "message"
                                (getf saved :message-id)
                                (jonathan:to-json (list :sessionId session-id
                                                        :senderType sender-type
                                                        :clientMsgId client-msg-id
                                                        :messageType msg-type)))
             (%json-response (list :ok t
                       :messageId (getf saved :message-id)
                       :clientMsgId client-msg-id)
                     201)))))))

(hunchentoot:define-easy-handler (session-presence-handler :uri "/api/v1/sessions/presence") (sessionId)
  (if (eql (hunchentoot:request-method*) :get)
      (let* ((sid (or sessionId ""))
             (idle-seconds (max 5 (%safe-int (runtime-config-get "presenceIdleSeconds" 30) 30))))
        (if (not (%non-empty-string-p sid))
            (%json-response (list :ok nil
                                  :error (list :code "INVALID_ARGUMENT"
                                               :message "sessionId is required"))
                            400)
            (let ((snapshot (session-presence-snapshot sid :idle-seconds idle-seconds)))
              (%json-response (list :ok t :presence snapshot) 200))))
      (%json-response (list :ok nil :error (list :code "METHOD_NOT_ALLOWED" :message "GET required")) 405)))

(hunchentoot:define-easy-handler (session-typing-handler :uri "/api/v1/sessions/typing") (sessionId)
  (if (eql (hunchentoot:request-method*) :get)
      (let* ((sid (or sessionId ""))
             (typing (session-typing-snapshot sid :idle-seconds 8)))
        (%json-response (list :ok t :typing typing) 200))
      (%json-response (list :ok nil :error (list :code "METHOD_NOT_ALLOWED" :message "GET required")) 405)))

(hunchentoot:define-easy-handler (files-upload-handler :uri "/api/v1/files/upload") ()
  (if (eql (hunchentoot:request-method*) :post)
      (let* ((data (%request-json))
             (limit-resp (%rate-limit-response "files.upload" *rate-limit-upload-max*))
             (session-id (or (%json-get data :sessionId)
                             (%json-get data :session-id)
                             ""))
             (filename (or (%json-get data :fileName)
                           (%json-get data :filename)
                           ""))
             (file-content (or (%json-get data :fileContent)
                               (%json-get data :content)
                               ""))
             (mime-type (or (%json-get data :mimeType)
                            (%json-get data :mime-type)
                            "application/octet-stream"))
             (file-size (%safe-int (or (%json-get data :fileSize)
                                       (%json-get data :size)
                                       (length file-content))
                                   (length file-content)))
             (sender-type (or (%json-get data :senderType)
                              (%json-get data :sender-type)
                              "visitor"))
             (agent-sub (%agent-auth-sub))
             (requested-uploader-id (or (%json-get data :uploaderId)
                          (%json-get data :uploader-id)
                          "visitor"))
             (uploader-id (%effective-uploader-id sender-type requested-uploader-id agent-sub))
             (client-msg-id (or (%json-get data :clientMsgId)
                                (%json-get data :client-msg-id)
                                "")))
        (cond
          (limit-resp limit-resp)
          ((or (not (%non-empty-string-p session-id))
               (not (%non-empty-string-p filename)))
           (%json-response
            (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "sessionId and fileName are required"))
            400))
          ((or (> (length session-id) *max-session-id-length*)
               (> (length filename) *max-filename-length*)
               (%path-traversal-name-p filename)
               (> (length mime-type) *max-mime-type-length*))
           (log-security-event "upload_validation_failed"
                               (list :session-id session-id :filename filename :mime-type mime-type))
           (%json-response
            (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "invalid file metadata"))
            400))
          ((or (not (%allowed-string-p sender-type '("visitor" "agent")))
               (not (%string-length<= uploader-id 64))
               (and (%non-empty-string-p client-msg-id)
                    (> (length client-msg-id) *max-client-msg-id-length*)))
           (%json-response
            (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "invalid sender or identifier"))
            400))
          ((and (string= (string-downcase sender-type) "agent")
             (null agent-sub))
           (log-security-event "upload_agent_sender_unauthorized" (list :session-id session-id))
           (%json-response
            (list :ok nil :error (list :code "AUTH_FORBIDDEN" :message "agent sender requires bearer token"))
            401))
          ((and (string= (string-downcase sender-type) "visitor")
             (%non-empty-string-p requested-uploader-id)
             (not (string= (%trimmed-string-or requested-uploader-id "") "visitor")))
           (log-security-event "upload_visitor_uploaderid_overridden"
                   (list :session-id session-id
                      :requested-uploader-id requested-uploader-id
                      :effective-uploader-id uploader-id))
           (let ((result (process-upload-and-send session-id
                          sender-type
                          uploader-id
                          filename
                          mime-type
                          file-size
                          file-content
                          :client-msg-id client-msg-id)))
             (if (getf result :ok)
              (%json-response result 201)
              (%json-response result 400))))
          (t
           (let ((result (process-upload-and-send session-id
                                                  sender-type
                                                  uploader-id
                                                  filename
                                                  mime-type
                                                  file-size
                                                  file-content
                                                  :client-msg-id client-msg-id)))
             (if (getf result :ok)
                 (%json-response result 201)
                 (%json-response result 400))))))
      (%json-response (list :ok nil :error (list :code "METHOD_NOT_ALLOWED" :message "POST required")) 405)))

(hunchentoot:define-easy-handler (auth-login-handler :uri "/api/v1/auth/login") ()
  (if (eql (hunchentoot:request-method*) :post)
      (let* ((data (%request-json))
             (limit-resp (%rate-limit-response "auth.login" *rate-limit-auth-max*))
             (username (or (%json-get data :username) ""))
             (password (or (%json-get data :password) ""))
             (result (agent-login username password)))
        (cond
          (limit-resp limit-resp)
          ((or (not (%non-empty-string-p username))
               (not (%non-empty-string-p password))
               (> (length username) *max-username-length*)
               (> (length password) *max-password-length*))
           (log-security-event "auth_login_invalid_payload" (list :username username))
           (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "invalid username or password")) 400))
          ((getf result :ok)
           (%json-response result 200))
          (t
           (%json-response result 401))))
      (%json-response (list :ok nil :error (list :code "METHOD_NOT_ALLOWED" :message "POST required")) 405)))

(hunchentoot:define-easy-handler (auth-change-password-handler :uri "/api/v1/auth/change-password") ()
  (if (eql (hunchentoot:request-method*) :post)
      (let* ((data (%request-json))
             (limit-resp (%rate-limit-response "auth.change-password" *rate-limit-auth-max*))
             (username (or (%json-get data :username) ""))
             (old-password (or (%json-get data :oldPassword)
                               (%json-get data :old-password)
                               ""))
             (new-password (or (%json-get data :newPassword)
                               (%json-get data :new-password)
                               ""))
             (result (change-admin-password username old-password new-password)))
        (cond
          (limit-resp limit-resp)
          ((or (not (%non-empty-string-p username))
               (not (%non-empty-string-p old-password))
               (not (%non-empty-string-p new-password))
               (> (length username) *max-username-length*)
               (> (length old-password) *max-password-length*)
               (> (length new-password) *max-password-length*))
           (log-security-event "auth_change_password_invalid_payload" (list :username username))
           (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "invalid password payload")) 400))
          ((getf result :ok)
           (%json-response result 200))
          (t
           (%json-response result 400))))
      (%json-response (list :ok nil :error (list :code "METHOD_NOT_ALLOWED" :message "POST required")) 405)))

(hunchentoot:define-easy-handler (quick-reply-groups-handler :uri "/api/v1/quick-reply-groups") ()
  (if (eql (hunchentoot:request-method*) :post)
      (let* ((data (%request-json))
             (name (or (%json-get data :name) (%json-get data :groupName) "")))
        (if (or (not (%non-empty-string-p name))
                (> (length name) 128))
            (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "name is required")) 400)
            (%json-response (list :ok t :group (create-quick-reply-group name)) 201)))
      (%json-response (list :ok t :groups (list-quick-reply-groups)) 200)))

(hunchentoot:define-easy-handler (quick-replies-handler :uri "/api/v1/quick-replies") (groupId)
  (if (eql (hunchentoot:request-method*) :post)
      (let* ((data (%request-json))
             (group-id (or (%json-get data :groupId)
                           (%json-get data :group-id)
                           groupId
                           ""))
             (content (or (%json-get data :content) "")))
        (if (or (not (%non-empty-string-p group-id))
                (not (%non-empty-string-p content))
                (> (length group-id) 64)
                (> (length content) *max-quick-reply-length*))
            (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "groupId and content are required")) 400)
            (handler-case
                (%json-response (list :ok t :reply (create-quick-reply group-id content)) 201)
              (error ()
                (%json-response (list :ok nil :error (list :code "GROUP_NOT_FOUND" :message "quick reply group not found")) 404)))))
      (%json-response (list :ok t :items (list-quick-replies groupId)) 200)))

    (hunchentoot:define-easy-handler (knowledge-snippets-handler :uri "/api/v1/knowledge/snippets") (q groupId limit)
      (if (eql (hunchentoot:request-method*) :get)
      (let* ((query (or q ""))
         (group-id (or groupId ""))
         (limit-num (max 1 (min 50 (%safe-int limit 20))))
         (items (%knowledge-search-items :query query
                     :group-id group-id
                     :limit limit-num)))
        (%json-response (list :ok t
              :query query
              :groupId group-id
              :limit limit-num
              :items items)
            200))
      (%json-response (list :ok nil :error (list :code "METHOD_NOT_ALLOWED" :message "GET required")) 405)))

(hunchentoot:define-easy-handler (macros-handler :uri "/api/v1/macros") ()
  (if (eql (hunchentoot:request-method*) :post)
      (let* ((data (%request-json))
             (title (or (%json-get data :title) ""))
             (reply-template (or (%json-get data :replyTemplate)
                                 (%json-get data :reply-template)
                                 ""))
             (actions (or (%json-get data :actions) '())))
        (if (or (not (%non-empty-string-p title))
                (not (%non-empty-string-p reply-template))
                (> (length title) 128)
                (> (length reply-template) *max-quick-reply-length*))
            (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "title and replyTemplate are required")) 400)
            (multiple-value-bind (ok _normalized reason) (validate-macro-actions actions)
              (declare (ignore _normalized))
              (if (not ok)
                  (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message (format nil "invalid macro actions: ~a" reason))) 400)
                  (%json-response (list :ok t :macro (create-macro title reply-template :actions actions)) 201)))))
      (%json-response (list :ok t :items (list-macros)) 200)))

(hunchentoot:define-easy-handler (session-attributes-handler :uri "/api/v1/sessions/attributes") (sessionId)
  (if (eql (hunchentoot:request-method*) :put)
      (let* ((data (%request-json))
             (sid (or (%json-get data :sessionId)
                      (%json-get data :session-id)
                      sessionId
                      ""))
             (attrs-input (%extract-session-attributes data)))
        (if (or (not (%non-empty-string-p sid))
                (> (length sid) *max-session-id-length*))
            (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "sessionId is required")) 400)
            (%json-response (list :ok t
                                  :sessionId sid
                                  :attributes (set-session-attributes sid attrs-input))
                            200)))
      (let ((sid (or sessionId "")))
        (if (%non-empty-string-p sid)
            (if (> (length sid) *max-session-id-length*)
                (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "sessionId is required")) 400)
                (%json-response (list :ok t
                                      :sessionId sid
                                      :attributes (get-session-attributes sid))
                                200))
            (let* ((issue-type (or (hunchentoot:parameter "issueType")
                                   (hunchentoot:parameter "issue-type")
                                   ""))
                   (urgency (or (hunchentoot:parameter "urgency") ""))
                   (language (or (hunchentoot:parameter "language") ""))
                   (customer-tier (or (hunchentoot:parameter "customerTier")
                                      (hunchentoot:parameter "customer-tier")
                                      ""))
                   (items (if (and (not (%non-empty-string-p issue-type))
                                   (not (%non-empty-string-p urgency))
                                   (not (%non-empty-string-p language))
                                   (not (%non-empty-string-p customer-tier)))
                              (list-session-attributes)
                              (find-session-attributes
                               :issue-type issue-type
                               :urgency urgency
                               :language language
                               :customer-tier customer-tier))))
              (%json-response (list :ok t :items items) 200))))))

(hunchentoot:define-easy-handler (agent-presence-handler :uri "/api/v1/agents/presence") ()
  (if (eql (hunchentoot:request-method*) :post)
      (let* ((data (%request-json))
             (agent-id (or (%json-get data :agentId) (%json-get data :agent-id) ""))
             (online-val (or (%json-get data :online) t))
             (capacity (max 1 (%safe-int (or (%json-get data :capacity) 5) 5))))
        (if (or (not (%non-empty-string-p agent-id))
                (> (length agent-id) 64)
                (> capacity 100))
            (%json-response (list :ok nil :error (list :code "INVALID_ARGUMENT" :message "agentId is required")) 400)
            (let ((online (not (member (string-downcase (princ-to-string online-val)) '("false" "0" "nil") :test #'string=))))
              (when online
                (set-agent-capacity agent-id capacity))
              (%json-response
               (list :ok t
                     :presence (if online
                                   (set-agent-online agent-id :capacity capacity)
                                   (set-agent-offline agent-id)))
               200))))
      (%json-response (list :ok t :agents (list-online-agents)) 200)))



(defun start-http-server ()
  (unless *acceptor*
    (let ((port (config-get :http-port 4000)))
      (setf *acceptor* (make-instance 'hunchentoot:easy-acceptor :port port))
      (hunchentoot:start *acceptor*)
      (log-info "HTTP server started" (list :port port))))
  *acceptor*)

(defun stop-http-server ()
  (when *acceptor*
    (hunchentoot:stop *acceptor*)
    (setf *acceptor* nil))
  t)

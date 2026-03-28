(defpackage #:cl-fly.tests.contract.p1-macro-attributes
  (:use #:cl #:fiveam)
  (:export #:run-p1-macro-attributes-contract-tests))

(in-package #:cl-fly.tests.contract.p1-macro-attributes)

(def-suite p1-macro-attributes-contract-suite
  :description "Contract checks for P1 macro and session attributes APIs.")

(in-suite p1-macro-attributes-contract-suite)

(defun %read-http-routes ()
  (uiop:read-file-string
   #p"d:/VSCode/project/cl-fly/src/api/http-routes.lisp"))

(test macro-api-endpoint-contract
  (let ((src (%read-http-routes)))
    (is-true (search "/api/v1/macros" src))
    (is-true (search ":replyTemplate" src))
    (is-true (search ":actions" src))
    (is-true (search "title and replyTemplate are required" src))
    (is-true (search "invalid macro actions" src))))

(test session-attributes-api-endpoint-contract
  (let ((src (%read-http-routes)))
    (is-true (search "/api/v1/sessions/attributes" src))
    (is-true (search ":issueType" src))
    (is-true (search ":customerTier" src))
    (is-true (search ":attributes" src))
    (is-true (search ":items" src))))

(test sessions-prechat-intent-contract
  (let ((src (%read-http-routes)))
    (is-true (search "%extract-prechat" src))
    (is-true (search ":intentScore" src))
    (is-true (search ":prechat" src))))

(test knowledge-snippets-api-contract
  (let ((src (%read-http-routes)))
    (is-true (search "/api/v1/knowledge/snippets" src))
    (is-true (search "%knowledge-search-items" src))
    (is-true (search ":groupName" src))))

(test internal-note-http-contract
  (let ((src (%read-http-routes)))
    (is-true (search "internal_note" src))
    (is-true (search "viewerType" src))
    (is-true (search "internal_note requires senderType=agent" src))))

(test macro-core-contract-shape
  (let* ((entry (cl-fly.core.macro:create-macro
                 "welcome-macro"
                 "Hello, how can I help?"
                 :actions (list :setTag "welcome" :setStatus "active")))
         (items (cl-fly.core.macro:list-macros))
         (found (find (getf entry :macroId) items :key (lambda (x) (getf x :macroId)) :test #'string=)))
    (is-true found)
    (is (string= "welcome-macro" (getf found :title)))
    (is (string= "Hello, how can I help?" (getf found :replyTemplate)))))

(test macro-core-invalid-actions-rejected
  (multiple-value-bind (ok _normalized reason)
      (cl-fly.core.macro:validate-macro-actions (list :unknown "x"))
    (declare (ignore _normalized))
    (is-false ok)
    (is (string= "unsupported action key" reason)))
  (multiple-value-bind (ok _normalized reason)
      (cl-fly.core.macro:validate-macro-actions (list :setPriority "extreme"))
    (declare (ignore _normalized))
    (is-false ok)
    (is (string= "invalid action value" reason)))
  (multiple-value-bind (ok _normalized reason)
      (cl-fly.core.macro:validate-macro-actions (list :setTag))
    (declare (ignore _normalized))
    (is-false ok)
    (is (string= "actions must be key/value pairs" reason)))
  (signals error
    (cl-fly.core.macro:create-macro "bad" "bad" :actions (list :setPriority "extreme"))))

(test session-attributes-core-contract-shape
  (let* ((sid (getf (cl-fly.core.session:ensure-session nil) :session-id))
         (updated (cl-fly.core.session-attributes:set-session-attributes
                   sid
                   (list :issueType "billing"
                         :urgency "high"
                         :language "zh-CN"
                         :customerTier "enterprise")))
         (loaded (cl-fly.core.session-attributes:get-session-attributes sid)))
    (is (string= sid (getf (cl-fly.core.session:ensure-session sid) :session-id)))
    (is (string= "billing" (getf updated :issueType)))
    (is (string= "enterprise" (getf loaded :customerTier)))))

(test session-prechat-intent-core-contract
  (let* ((sid (getf (cl-fly.core.session:ensure-session nil) :session-id))
         (updated (cl-fly.core.session:set-session-prechat
                   sid
                   :issue-type "billing"
                   :urgency "urgent"
                   :language "zh-CN"
                   :customer-tier "vip"))
         (snapshot (cl-fly.core.session:session-prechat-snapshot sid))
         (score (cl-fly.core.session:session-intent-score sid)))
    (is (string= "billing" (getf snapshot :issueType)))
    (is (string= "urgent" (getf snapshot :urgency)))
    (is (string= "vip" (getf snapshot :customerTier)))
    (is (>= score 80))
    (is (= score (getf updated :intent-score)))))

(test knowledge-snippets-search-core-contract
  (let* ((group (cl-fly.core.quick-reply:create-quick-reply-group "billing"))
         (gid (getf group :groupId))
         (_r1 (cl-fly.core.quick-reply:create-quick-reply gid "billing refund policy {{sessionId}}"))
         (_r2 (cl-fly.core.quick-reply:create-quick-reply gid "tech setup steps"))
         (items (cl-fly.api.http::%knowledge-search-items :query "billing refund" :group-id gid :limit 10))
         (contents (mapcar (lambda (x) (getf x :content)) items)))
    (declare (ignore _r1 _r2))
    (is-true (find "billing refund policy {{sessionId}}" contents :test #'string=))
    (is-false (find "tech setup steps" contents :test #'string=))))

(test internal-note-mentions-core-contract
  (let* ((sid (getf (cl-fly.core.session:ensure-session nil) :session-id))
         (_visitor (cl-fly.core.message:send-message sid "visitor" "text" "hello" :client-msg-id "p1-note-v"))
         (saved (cl-fly.core.message:send-message sid "agent" "internal_note" "sync with @alice and @bob about @alice" :client-msg-id "p1-note-a"))
         (mentions (getf saved :mentions)))
    (declare (ignore _visitor))
    (is-true (find "alice" mentions :test #'string=))
    (is-true (find "bob" mentions :test #'string=))
    (is (= 2 (length mentions)))))

(test internal-note-ws-contract
  (let* ((sid (getf (cl-fly.core.session:ensure-session nil) :session-id))
         (agent-res (cl-fly.api.ws-agent:handle-agent-event
                     "agent-note-1"
                     "message.send"
                     (list :sessionId sid :messageType "internal_note" :content "note @charlie" :clientMsgId "ws-note-1")))
         (agent-ack (getf agent-res :payload))
         (visitor-res (cl-fly.api.ws-visitor:handle-visitor-event
                       "visitor-note-1"
                       "message.send"
                       (list :sessionId sid :messageType "internal_note" :content "bad" :clientMsgId "ws-note-2"))))
    (is (string= "ack" (getf agent-res :event)))
    (is-true (find "charlie" (getf agent-ack :mentions) :test #'string=))
    (is (string= "error" (getf visitor-res :event)))
    (is (string= "INVALID_ARGUMENT" (getf (getf visitor-res :payload) :code)))))

(test internal-note-visitor-replay-visibility
  (let* ((sid (getf (cl-fly.core.session:ensure-session nil) :session-id))
         (_v1 (cl-fly.core.message:send-message sid "visitor" "text" "public-text" :client-msg-id "rep-v-1"))
         (_n1 (cl-fly.core.message:send-message sid "agent" "internal_note" "hidden-note @ops" :client-msg-id "rep-n-1"))
         (replay (cl-fly.api.ws-visitor:handle-visitor-event
                  "visitor-replay-1"
                  "session.replay"
                  (list :sessionId sid)))
         (payload (getf replay :payload))
         (messages (getf payload :messages))
         (types (mapcar (lambda (x) (string-downcase (or (getf x :message-type) "text"))) messages)))
    (declare (ignore _v1 _n1))
    (is (string= "session.replay" (getf replay :event)))
    (is-true (find "text" types :test #'string=))
    (is-false (find "internal_note" types :test #'string=))))

(test session-attributes-filtering-contract
  (let* ((sid-1 (getf (cl-fly.core.session:ensure-session nil) :session-id))
         (sid-2 (getf (cl-fly.core.session:ensure-session nil) :session-id))
         (_1 (cl-fly.core.session-attributes:set-session-attributes
              sid-1
              (list :issueType "billing" :urgency "high" :language "zh-CN" :customerTier "enterprise")))
         (_2 (cl-fly.core.session-attributes:set-session-attributes
              sid-2
              (list :issueType "tech" :urgency "low" :language "en-US" :customerTier "standard")))
         (billing-items (cl-fly.core.session-attributes:find-session-attributes :issue-type "billing"))
         (enterprise-items (cl-fly.core.session-attributes:find-session-attributes :customer-tier "enterprise"))
         (missing-items (cl-fly.core.session-attributes:find-session-attributes :issue-type "no-such-type")))
    (declare (ignore _1 _2))
    (is-true (find sid-1 billing-items :key (lambda (x) (getf x :sessionId)) :test #'string=))
    (is-false (find sid-2 billing-items :key (lambda (x) (getf x :sessionId)) :test #'string=))
    (is-true (find sid-1 enterprise-items :key (lambda (x) (getf x :sessionId)) :test #'string=))
    (is (= 0 (length missing-items)))))

(defun run-p1-macro-attributes-contract-tests ()
  (run! 'p1-macro-attributes-contract-suite))

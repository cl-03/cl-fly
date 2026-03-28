(in-package #:cl-fly.core.session)

(defparameter *sessions* (make-hash-table :test 'equal))
(defparameter *sessions-lock* (bt:make-lock "session-store-lock"))
(defparameter *typing-by-session* (make-hash-table :test 'equal))
(defparameter *typing-lock* (bt:make-lock "session-typing-lock"))
(defparameter *sla-first-reply-sec* 120)
(defparameter *sla-next-reply-sec* 300)

(defparameter +unix-epoch-offset+ 2208988800)
(defparameter *session-seq* 0)
(defparameter *session-seq-lock* (bt:make-lock "session-seq-lock"))

(defparameter *urgency-intent-map*
  '(("low" . 10)
    ("normal" . 30)
    ("high" . 60)
    ("urgent" . 85)))

(defparameter *customer-tier-intent-map*
  '(("standard" . 0)
    ("enterprise" . 12)
    ("vip" . 20)))

(defparameter *issue-type-intent-map*
  '(("billing" . 16)
    ("tech" . 12)
    ("product" . 8)))

(defun %sla-state (due-at now)
  (if (or (null due-at) (<= due-at 0))
      (values "healthy" nil)
      (let ((remaining (- due-at now)))
        (cond
          ((< remaining 0) (values "breached" remaining))
          ((<= remaining 30) (values "at-risk" remaining))
          (t (values "healthy" remaining))))))

(defun %session-sla-snapshot (session now)
  (let* ((first-reply-at (getf session :first-reply-at))
         (first-reply-due-at (getf session :first-reply-due-at))
         (next-reply-due-at (getf session :next-reply-due-at))
         (due-at (if first-reply-at next-reply-due-at first-reply-due-at))
         (state nil)
         (remaining nil))
    (multiple-value-setq (state remaining) (%sla-state due-at now))
    (list :firstReplyAt first-reply-at
          :firstReplyAtUnix (and first-reply-at (- first-reply-at +unix-epoch-offset+))
          :firstReplyDueAt first-reply-due-at
          :firstReplyDueAtUnix (and first-reply-due-at (- first-reply-due-at +unix-epoch-offset+))
          :nextReplyDueAt next-reply-due-at
          :nextReplyDueAtUnix (and next-reply-due-at (- next-reply-due-at +unix-epoch-offset+))
          :activeDueAt due-at
          :activeDueAtUnix (and due-at (- due-at +unix-epoch-offset+))
          :state state
          :remainingSec remaining)))

(defun session-count ()
  (bt:with-lock-held (*sessions-lock*)
    (hash-table-count *sessions*)))

(defun list-sessions ()
  (bt:with-lock-held (*sessions-lock*)
    (let ((items '()))
      (maphash (lambda (_id session)
                 (declare (ignore _id))
                 (push (copy-list session) items))
               *sessions*)
      (sort items #'> :key (lambda (s) (or (getf s :last-activity-at) 0))))))

(defun %new-session-id ()
  (bt:with-lock-held (*session-seq-lock*)
    (incf *session-seq*)
    (format nil "s-~d-~d" (get-universal-time) *session-seq*)))

(defun %blank-string-p (value)
  (and (stringp value)
       (string= (string-trim '(#\Space #\Tab #\Newline #\Return) value) "")))

(defun %normalize-prechat-value (value)
  (let ((trimmed (if (stringp value)
                     (string-trim '(#\Space #\Tab #\Newline #\Return) value)
                     "")))
    (if (string= trimmed "") nil trimmed)))

(defun %normalize-enum-value (value allowed)
  (let ((normalized (and (stringp value)
                         (string-downcase (string-trim '(#\Space #\Tab #\Newline #\Return) value)))))
    (if (and normalized
             (member normalized allowed :test #'string=))
        normalized
        nil)))

(defun %inc-agent-counter (alist agent-id &optional (delta 1))
  (if (or (not (stringp agent-id))
          (string= (string-trim '(#\Space #\Tab #\Newline #\Return) agent-id) ""))
      alist
      (let ((cell (assoc agent-id alist :test #'string=)))
        (if cell
            (progn
              (setf (cdr cell) (+ (or (cdr cell) 0) delta))
              alist)
            (acons agent-id delta alist)))))

(defun %safe-int (value &optional default)
  (handler-case
      (etypecase value
        (integer value)
        (float (round value))
        (string (parse-integer value :junk-allowed t)))
    (error () default)))

(defun %intent-map-lookup (value table)
  (or (cdr (assoc (or value "") table :test #'string=)) 0))

(defun %default-intent-score (issue-type urgency customer-tier)
  (let ((score (+ (%intent-map-lookup urgency *urgency-intent-map*)
                  (%intent-map-lookup customer-tier *customer-tier-intent-map*)
                  (%intent-map-lookup issue-type *issue-type-intent-map*))))
    (min 100 (max 0 score))))

(defun %clamp-intent-score (value)
  (let ((n (%safe-int value nil)))
    (if (null n)
        nil
        (max 0 (min 100 n)))))

(defun %session-prechat (session)
  (let ((issue-type (or (getf session :issue-type) ""))
        (urgency (or (getf session :urgency) ""))
        (language (or (getf session :language) ""))
        (customer-tier (or (getf session :customer-tier) "")))
    (list :issueType issue-type
          :urgency urgency
          :language language
          :customerTier customer-tier)))

(defun ensure-session (&optional session-id)
  (let* ((sid (if (or (null session-id) (%blank-string-p session-id))
                  (%new-session-id)
                  session-id))
         (now (get-universal-time))
         (existing (bt:with-lock-held (*sessions-lock*)
                     (gethash sid *sessions*)) ))
    (or existing
        (bt:with-lock-held (*sessions-lock*)
          (or (gethash sid *sessions*)
              (let ((session (list :session-id sid
                                   :status "queued"
                                   :assignee nil
                                   :welcome-message (cl-fly.core.config:welcome-message)
                                   :issue-type ""
                                   :urgency "normal"
                                   :language ""
                                   :customer-tier "standard"
                                   :intent-score 30
                                   :visitor-touch-count 0
                                   :agent-touch-count 0
                                   :handoff-count 0
                                   :reopen-count 0
                                   :agent-touch-counts '()
                                   :agent-handoff-counts '()
                                   :last-visitor-touch-at nil
                                   :last-agent-touch-at nil
                                   :last-agent-touch-by nil
                                   :created-at now
                                   :last-activity-at now
                                   :visitor-last-active-at now
                                   :agent-last-active-at nil
                                   :first-reply-at nil
                                   :first-reply-due-at (+ now *sla-first-reply-sec*)
                                   :next-reply-due-at nil)))
                (setf (gethash sid *sessions*) session)
                session))))))

(defun set-session-prechat (session-id &key issue-type urgency language customer-tier intent-score)
  (ensure-session session-id)
  (bt:with-lock-held (*sessions-lock*)
    (let* ((session (gethash session-id *sessions*))
           (normalized-issue-type
            (%normalize-enum-value issue-type '("billing" "tech" "product")))
           (normalized-urgency
            (%normalize-enum-value urgency '("low" "normal" "high" "urgent")))
           (normalized-language
            (%normalize-prechat-value language))
           (normalized-customer-tier
            (%normalize-enum-value customer-tier '("standard" "enterprise" "vip")))
           (effective-issue-type (or normalized-issue-type (getf session :issue-type) ""))
           (effective-urgency (or normalized-urgency (getf session :urgency) "normal"))
           (effective-language (or normalized-language (getf session :language) ""))
           (effective-customer-tier (or normalized-customer-tier (getf session :customer-tier) "standard"))
           (effective-intent-score
            (or (%clamp-intent-score intent-score)
                (%default-intent-score effective-issue-type effective-urgency effective-customer-tier))))
      (setf (getf session :issue-type) effective-issue-type)
      (setf (getf session :urgency) effective-urgency)
      (setf (getf session :language) effective-language)
      (setf (getf session :customer-tier) effective-customer-tier)
      (setf (getf session :intent-score) effective-intent-score)
      (setf (gethash session-id *sessions*) session)
      session)))

(defun session-intent-score (session-id)
  (bt:with-lock-held (*sessions-lock*)
    (or (getf (gethash session-id *sessions*) :intent-score) 0)))

(defun session-prechat-snapshot (session-id)
  (bt:with-lock-held (*sessions-lock*)
    (let ((session (gethash session-id *sessions*)))
      (if session
          (%session-prechat session)
          (list :issueType "" :urgency "normal" :language "" :customerTier "standard")))))

(defun touch-session-activity (session-id role)
  (ensure-session session-id)
  (let ((now (get-universal-time)))
    (bt:with-lock-held (*sessions-lock*)
      (let ((session (gethash session-id *sessions*)))
        (setf (getf session :last-activity-at) now)
        (when (and role (stringp role))
          (cond
            ((string-equal role "visitor")
             (let ((last-touch (getf session :last-visitor-touch-at)))
               (when (or (null last-touch)
                         (>= (- now last-touch) 5))
                 (setf (getf session :visitor-touch-count)
                       (1+ (or (getf session :visitor-touch-count) 0)))
                 (setf (getf session :last-visitor-touch-at) now)
                 (when (and (getf session :first-reply-at)
                            (getf session :agent-last-active-at)
                            (>= (- now (or (getf session :agent-last-active-at) now)) 300))
                   (setf (getf session :reopen-count)
                         (1+ (or (getf session :reopen-count) 0))))))
             (setf (getf session :visitor-last-active-at) now)
             (setf (getf session :next-reply-due-at) (+ now *sla-next-reply-sec*)))
            ((string-equal role "agent")
             (let* ((last-touch (getf session :last-agent-touch-at))
                    (agent-id (or (getf session :assignee) ""))
                    (last-agent (or (getf session :last-agent-touch-by) ""))
                    (should-count (or (null last-touch)
                                      (>= (- now last-touch) 5)
                                      (not (string= agent-id last-agent)))))
               (when should-count
                 (setf (getf session :agent-touch-count)
                       (1+ (or (getf session :agent-touch-count) 0)))
                 (setf (getf session :agent-touch-counts)
                       (%inc-agent-counter
                        (or (getf session :agent-touch-counts) '())
                        agent-id
                        1))
                 (setf (getf session :last-agent-touch-at) now)
                 (setf (getf session :last-agent-touch-by) agent-id)))
             (setf (getf session :agent-last-active-at) now)
             (unless (getf session :first-reply-at)
               (setf (getf session :first-reply-at) now))
             (setf (getf session :next-reply-due-at) nil))))
        (setf (gethash session-id *sessions*) session)
        session))))

(defun session-presence-snapshot (session-id &key (idle-seconds 30))
  (if (%blank-string-p session-id)
      (list :sessionId ""
            :status "missing"
            :assignee nil
            :idleThresholdSec idle-seconds
            :lastActivityAt nil
            :lastActivityUnix nil
            :lastActivityAgeSec nil
            :visitorLastActiveAt nil
            :visitorLastActiveUnix nil
            :visitorLastActiveAgeSec nil
            :agentLastActiveAt nil
            :agentLastActiveUnix nil
            :agentLastActiveAgeSec nil
            :visitorOnline nil
            :agentOnline nil
            :sla (list :firstReplyAt nil
                       :firstReplyAtUnix nil
                       :firstReplyDueAt nil
                       :firstReplyDueAtUnix nil
                       :nextReplyDueAt nil
                       :nextReplyDueAtUnix nil
                       :activeDueAt nil
                       :activeDueAtUnix nil
                       :state "healthy"
                       :remainingSec nil))
      (let* ((session (ensure-session session-id))
         (now (get-universal-time))
         (visitor-ts (getf session :visitor-last-active-at))
         (agent-ts (getf session :agent-last-active-at))
         (last-ts (or (getf session :last-activity-at) (getf session :created-at) now))
         (last-unix (- last-ts +unix-epoch-offset+))
         (visitor-unix (and visitor-ts (- visitor-ts +unix-epoch-offset+)))
         (agent-unix (and agent-ts (- agent-ts +unix-epoch-offset+)))
         (visitor-age (if visitor-ts (- now visitor-ts) nil))
           (agent-age (if agent-ts (- now agent-ts) nil))
           (last-age (max 0 (- now last-ts)))
           (sla (%session-sla-snapshot session now)))
    (list :sessionId (getf session :session-id)
          :status (getf session :status)
          :assignee (getf session :assignee)
          :idleThresholdSec idle-seconds
          :lastActivityAt last-ts
          :lastActivityUnix last-unix
          :lastActivityAgeSec last-age
          :visitorLastActiveAt visitor-ts
          :visitorLastActiveUnix visitor-unix
          :visitorLastActiveAgeSec visitor-age
          :agentLastActiveAt agent-ts
          :agentLastActiveUnix agent-unix
          :agentLastActiveAgeSec agent-age
          :visitorOnline (and visitor-age (<= visitor-age idle-seconds))
          :agentOnline (and agent-age (<= agent-age idle-seconds))
          :sla sla))))

(defun set-session-typing (session-id from content)
  (let* ((sid (or session-id ""))
         (txt (if (stringp content)
                  (string-trim '(#\Space #\Tab #\Newline #\Return) content)
                  "")))
    (when (%blank-string-p sid)
      (return-from set-session-typing nil))
    (touch-session-activity sid from)
    (bt:with-lock-held (*typing-lock*)
      (if (%blank-string-p txt)
          (remhash sid *typing-by-session*)
          (setf (gethash sid *typing-by-session*)
                (list :session-id sid
                      :from (or from "visitor")
                      :content txt
                      :updated-at (get-universal-time))))
      (gethash sid *typing-by-session*))))

(defun session-typing-snapshot (session-id &key (idle-seconds 8))
  (let* ((sid (or session-id ""))
         (now (get-universal-time)))
    (if (%blank-string-p sid)
        (list :sessionId sid :active nil)
        (bt:with-lock-held (*typing-lock*)
          (let* ((entry (gethash sid *typing-by-session*))
                 (ts (and entry (getf entry :updated-at)))
                 (age (and ts (max 0 (- now ts))))
                 (active (and entry
                              age
                              (<= age idle-seconds)
                              (not (%blank-string-p (getf entry :content))))))
            (if (not active)
                (progn
                  (when entry (remhash sid *typing-by-session*))
                  (list :sessionId sid
                        :active nil
                        :idleThresholdSec idle-seconds))
                (list :sessionId sid
                      :active t
                      :from (getf entry :from)
                      :content (getf entry :content)
                      :updatedAt ts
                      :updatedAtUnix (- ts +unix-epoch-offset+)
                      :ageSec age
                      :idleThresholdSec idle-seconds)))))))

(defun session-status (session-id)
  (bt:with-lock-held (*sessions-lock*)
    (getf (gethash session-id *sessions*) :status)))

(defun session-assignee (session-id)
  (bt:with-lock-held (*sessions-lock*)
    (getf (gethash session-id *sessions*) :assignee)))

(defun accept-session (session-id agent-id)
  (ensure-session session-id)
  (bt:with-lock-held (*sessions-lock*)
    (let ((session (gethash session-id *sessions*)))
      (setf (getf session :status) "active")
      (setf (getf session :assignee) agent-id)
      (setf (gethash session-id *sessions*) session)
      session))
  (touch-session-activity session-id "agent")
  (bt:with-lock-held (*sessions-lock*)
    (gethash session-id *sessions*)))

(defun transfer-session (session-id to-agent-id)
  (ensure-session session-id)
  (bt:with-lock-held (*sessions-lock*)
    (let ((session (gethash session-id *sessions*)))
      (let ((from-agent (or (getf session :assignee) "")))
        (setf (getf session :agent-handoff-counts)
              (%inc-agent-counter
               (or (getf session :agent-handoff-counts) '())
               from-agent
               1)))
      (setf (getf session :assignee) to-agent-id)
      (setf (getf session :handoff-count)
            (1+ (or (getf session :handoff-count) 0)))
      (setf (gethash session-id *sessions*) session)
      session)))

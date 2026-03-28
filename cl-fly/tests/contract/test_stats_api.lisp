(defpackage #:cl-fly.tests.contract.stats-api
  (:use #:cl #:fiveam)
  (:export #:run-stats-api-contract-tests))

(in-package #:cl-fly.tests.contract.stats-api)

(def-suite stats-api-contract-suite
  :description "Contract checks for stats overview API.")

(in-suite stats-api-contract-suite)

(defun %read-openapi ()
  (uiop:read-file-string
   #p"d:/VSCode/project/specs/001-cl-online-kefu/contracts/openapi.yaml"))

(test stats-overview-endpoint-exists
  (let ((spec (%read-openapi)))
    (is-true (search "/api/v1/stats/overview:" spec))
    (is-true (search "summary: Overview statistics" spec))
    (is-true (search "bearerAuth" spec))
    (is-true (search "'200':" spec))))

(test stats-overview-dashboard-shape
  (let* ((sid (getf (cl-fly.core.session:ensure-session nil) :session-id))
         (_a1 (cl-fly.core.session:accept-session sid "agent-a"))
         (_t1 (cl-fly.core.session:touch-session-activity sid "agent"))
         (_t2 (cl-fly.core.session:touch-session-activity sid "visitor"))
         (_h1 (cl-fly.core.session:transfer-session sid "agent-b"))
         (overview (cl-fly.core.stats:overview-stats))
         (routing (getf overview :routingDashboard))
         (touches (getf overview :touchesDashboard)))
    (declare (ignore _a1 _t1 _t2 _h1))
    (is-true (listp routing))
    (is-true (listp touches))
    (is (>= (or (getf routing :handoffTotal) 0) 1))
    (is (>= (or (getf touches :totalTouches) 0) 1))))

(test inbox-analytics-current-agent-attribution
  (let* ((sid (getf (cl-fly.core.session:ensure-session nil) :session-id))
         (_a1 (cl-fly.core.session:accept-session sid "agent-a"))
         (_t1 (cl-fly.core.session:touch-session-activity sid "agent"))
         (_h1 (cl-fly.core.session:transfer-session sid "agent-b"))
         (_t2 (cl-fly.core.session:touch-session-activity sid "agent"))
         (sessions (cl-fly.core.session:list-sessions))
         (a-analytics (cl-fly.api.http::%analytics-summary sessions :agent-id "agent-a"))
         (b-analytics (cl-fly.api.http::%analytics-summary sessions :agent-id "agent-b"))
         (a-current (getf a-analytics :currentAgent))
         (b-current (getf b-analytics :currentAgent)))
    (declare (ignore _a1 _t1 _h1 _t2))
    (is (>= (or (getf a-current :myHandoff) 0) 1))
    (is (>= (or (getf a-current :myTouches) 0) 1))
    (is (>= (or (getf b-current :myTouches) 0) 1))))

(defun run-stats-api-contract-tests ()
  (run! 'stats-api-contract-suite))

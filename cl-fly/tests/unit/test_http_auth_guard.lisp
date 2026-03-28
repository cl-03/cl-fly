(defpackage #:cl-fly.tests.unit.http-auth-guard
  (:use #:cl #:fiveam)
  (:import-from #:cl-fly.auth.jwt
                #:issue-token)
  (:export #:run-http-auth-guard-unit-tests))

(in-package #:cl-fly.tests.unit.http-auth-guard)

(def-suite http-auth-guard-unit-suite
  :description "Unit checks for HTTP bearer auth guard helpers.")

(in-suite http-auth-guard-unit-suite)

(test bearer-token-extraction
  (is (string= "abc" (cl-fly.api.http::%bearer-token-from-header "Bearer abc")))
  (is-false (cl-fly.api.http::%bearer-token-from-header "Basic abc"))
  (is-false (cl-fly.api.http::%bearer-token-from-header "Bearer   ")))

(test agent-request-authorization
  (let ((agent-token (issue-token "agent-1" :role "agent" :ttl-seconds 60))
        (admin-token (issue-token "admin-1" :role "admin" :ttl-seconds 60))
        (visitor-token (issue-token "visitor-1" :role "visitor" :ttl-seconds 60)))
    (is-true (cl-fly.api.http::%agent-request-authorized-p (format nil "Bearer ~a" agent-token)))
    (is-true (cl-fly.api.http::%agent-request-authorized-p (format nil "Bearer ~a" admin-token)))
    (is-false (cl-fly.api.http::%agent-request-authorized-p (format nil "Bearer ~a" visitor-token)))
    (is-false (cl-fly.api.http::%agent-request-authorized-p "Bearer invalid.token.value"))))

(test agent-auth-sub-extraction
  (let ((agent-token (issue-token "agent-42" :role "agent" :ttl-seconds 60))
        (visitor-token (issue-token "visitor-42" :role "visitor" :ttl-seconds 60)))
    (is (string= "agent-42"
                 (cl-fly.api.http::%agent-auth-sub (format nil "Bearer ~a" agent-token))))
    (is-false (cl-fly.api.http::%agent-auth-sub (format nil "Bearer ~a" visitor-token)))
    (is-false (cl-fly.api.http::%agent-auth-sub "Bearer invalid.token.value"))))

(defun run-http-auth-guard-unit-tests ()
  (run! 'http-auth-guard-unit-suite))

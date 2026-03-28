(defpackage #:cl-fly.tests.unit.http-routes-validation
  (:use #:cl #:fiveam)
  (:export #:run-http-routes-validation-unit-tests))

(in-package #:cl-fly.tests.unit.http-routes-validation)

(def-suite http-routes-validation-unit-suite
  :description "Unit checks for HTTP route numeric parsing safeguards.")

(in-suite http-routes-validation-unit-suite)

(test safe-int-invalid-string-falls-back
  (is (= 20 (cl-fly.api.http::%safe-int "abc" 20)))
  (is (= 5 (cl-fly.api.http::%safe-int "" 5))))

(test safe-int-valid-string-and-int
  (is (= 12 (cl-fly.api.http::%safe-int "12" 0)))
  (is (= 7 (cl-fly.api.http::%safe-int 7 0))))

(test effective-uploader-id-binds-visitor
  (is (string= "visitor" (cl-fly.api.http::%effective-uploader-id "visitor" "admin")))
  (is (string= "visitor" (cl-fly.api.http::%effective-uploader-id "visitor" "   "))))

(test effective-uploader-id-normalizes-agent
  (is (string= "agent-1" (cl-fly.api.http::%effective-uploader-id "agent" "  agent-1  ")))
  (is (string= "agent" (cl-fly.api.http::%effective-uploader-id "agent" "   "))))

(test effective-uploader-id-prefers-agent-sub
  (is (string= "agent-from-token"
               (cl-fly.api.http::%effective-uploader-id "agent" "spoofed-agent" "agent-from-token")))
  (is (string= "agent-fallback"
               (cl-fly.api.http::%effective-uploader-id "agent" "agent-fallback" nil))))

(defun run-http-routes-validation-unit-tests ()
  (run! 'http-routes-validation-unit-suite))

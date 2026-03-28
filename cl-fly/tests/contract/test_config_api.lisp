(defpackage #:cl-fly.tests.contract.config-api
  (:use #:cl #:fiveam)
  (:export #:run-config-api-contract-tests))

(in-package #:cl-fly.tests.contract.config-api)

(def-suite config-api-contract-suite
  :description "Contract checks for runtime config API.")

(in-suite config-api-contract-suite)

(defun %read-openapi ()
  (uiop:read-file-string
   #p"d:/VSCode/project/specs/001-cl-online-kefu/contracts/openapi.yaml"))

(test config-endpoint-exists
  (let ((spec (%read-openapi)))
    (is-true (search "/api/v1/config:" spec))
    (is-true (search "summary: Get runtime config" spec))
    (is-true (search "summary: Update runtime config" spec))
    (is-true (search "welcomeMessage" spec))
    (is-true (search "'200':" spec))))

(defun run-config-api-contract-tests ()
  (run! 'config-api-contract-suite))

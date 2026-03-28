(defpackage #:cl-fly.tests.contract.auth-login
  (:use #:cl #:fiveam)
  (:export #:run-auth-login-contract-tests))

(in-package #:cl-fly.tests.contract.auth-login)

(def-suite auth-login-contract-suite
  :description "Contract checks for auth login API based on OpenAPI spec.")

(in-suite auth-login-contract-suite)

(defun %read-openapi ()
  (uiop:read-file-string
   #p"d:/VSCode/project/specs/001-cl-online-kefu/contracts/openapi.yaml"))

(test auth-login-endpoint-exists
  (let ((spec (%read-openapi)))
    (is-true (search "/api/v1/auth/login:" spec))
    (is-true (search "required: [username, password]" spec))
    (is-true (search "'200':" spec))
    (is-true (search "'401':" spec))))

(test auth-login-contract-fields
  (let ((spec (%read-openapi)))
    (is-true (search "summary: Agent login" spec))
    (is-true (search "application/json:" spec))
    (is-true (search "username: { type: string }" spec))
    (is-true (search "password: { type: string }" spec))))

(defun run-auth-login-contract-tests ()
  (run! 'auth-login-contract-suite))

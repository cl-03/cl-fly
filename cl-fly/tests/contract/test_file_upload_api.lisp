(defpackage #:cl-fly.tests.contract.file-upload-api
  (:use #:cl #:fiveam)
  (:export #:run-file-upload-api-contract-tests))

(in-package #:cl-fly.tests.contract.file-upload-api)

(def-suite file-upload-api-contract-suite
  :description "Contract checks for file upload API based on OpenAPI spec.")

(in-suite file-upload-api-contract-suite)

(defun %read-openapi ()
  (uiop:read-file-string
   #p"d:/VSCode/project/specs/001-cl-online-kefu/contracts/openapi.yaml"))

(test file-upload-endpoint-contract
  (let ((spec (%read-openapi)))
    (is-true (search "/api/v1/files/upload:" spec))
    (is-true (search "summary: Upload file" spec))
    (is-true (search "multipart/form-data" spec))
    (is-true (search "required: [file, sessionId]" spec))
    (is-true (search "'201':" spec))
    (is-true (search "'400':" spec))))

(defun run-file-upload-api-contract-tests ()
  (run! 'file-upload-api-contract-suite))

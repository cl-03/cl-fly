(defpackage #:cl-fly.tests.contract.messages
  (:use #:cl #:fiveam)
  (:export #:run-messages-contract-tests))

(in-package #:cl-fly.tests.contract.messages)

(def-suite messages-contract-suite
  :description "Contract checks for message APIs based on OpenAPI spec.")

(in-suite messages-contract-suite)

(defun %read-openapi ()
  (uiop:read-file-string
   #p"d:/VSCode/project/specs/001-cl-online-kefu/contracts/openapi.yaml"))

(test messages-send-endpoint-exists
  (let ((spec (%read-openapi)))
    (is-true (search "/api/v1/messages:" spec))
    (is-true (search "messageType" spec))
    (is-true (search "clientMsgId" spec))
    (is-true (search "'201':" spec))))

(test file-upload-endpoint-exists
  (let ((spec (%read-openapi)))
    (is-true (search "/api/v1/files/upload:" spec))
    (is-true (search "multipart/form-data" spec))
    (is-true (search "FILE_TOO_LARGE" (uiop:read-file-string #p"d:/VSCode/project/specs/001-cl-online-kefu/contracts/websocket-events.md")))))

(defun run-messages-contract-tests ()
  (run! 'messages-contract-suite))

(defpackage #:cl-fly.tests.unit.upload-policy
  (:use #:cl #:fiveam)
  (:export #:run-upload-policy-unit-tests))

(in-package #:cl-fly.tests.unit.upload-policy)

(def-suite upload-policy-unit-suite
  :description "Unit checks for file type/size validation policy.")

(in-suite upload-policy-unit-suite)

(test validate-upload-accepts-supported-file
  (let ((result (cl-fly.infra.storage:validate-upload "a.png" 1024)))
    (is-true (getf result :ok))))

(test validate-upload-rejects-unsupported-type
  (let ((result (cl-fly.infra.storage:validate-upload "a.exe" 1024)))
    (is-false (getf result :ok))
    (is (string= "UNSUPPORTED_FILE_TYPE" (getf result :code)))))

(test validate-upload-rejects-oversize-file
  (let ((result (cl-fly.infra.storage:validate-upload "a.png" (* 15 1024 1024))))
    (is-false (getf result :ok))
    (is (string= "FILE_TOO_LARGE" (getf result :code)))))

(defun run-upload-policy-unit-tests ()
  (run! 'upload-policy-unit-suite))

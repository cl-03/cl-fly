(defpackage #:cl-fly.tests.perf.sc002
  (:use #:cl)
  (:export #:run-sc002-gate))

(in-package #:cl-fly.tests.perf.sc002)

(defun %env (name default)
  (or (uiop:getenv name) default))

(defun %env-int (name default)
  (parse-integer (%env name (princ-to-string default)) :junk-allowed t))

(defun %write-report (total success success-rate threshold)
  (let* ((dir #p"d:/VSCode/project/cl-fly/tests/perf/reports/")
         (path (merge-pathnames "sc002-latest.txt" dir)))
    (ensure-directories-exist dir)
    (with-open-file (out path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (format out "scenario=sc002~%")
      (format out "total=~d~%" total)
      (format out "success=~d~%" success)
      (format out "success_rate=~,2f~%" success-rate)
      (format out "threshold=~,2f~%" threshold)
      (format out "generated_at_unix=~d~%" (get-universal-time)))
    path))

(defun run-sc002-gate ()
  "T064: assert first-message success rate gate is >= 98%."
  (let* ((sample-size (%env-int "KEFU_SC002_SAMPLE_SIZE" 500))
         (threshold (float (%env-int "KEFU_SC002_SUCCESS_RATE" 98)))
         (success 0))
    (dotimes (i sample-size)
      (let* ((client-id (format nil "rate-visitor-~d" i))
             (sid (format nil "rate-session-~d" i))
             (init-res (cl-fly.api.ws-visitor:handle-visitor-event
                        client-id
                        "session.init"
                        (list :sessionId sid)))
             (send-res (cl-fly.api.ws-visitor:handle-visitor-event
                        client-id
                        "message.send"
                        (list :sessionId sid
                              :messageType "text"
                              :content "hello"
                              :clientMsgId (format nil "fm-~d" i)))))
        (when (and (string= "session.ready" (getf init-res :event))
                   (string= "ack" (getf send-res :event)))
          (incf success))))
    (let* ((success-rate (* 100.0 (/ success sample-size)))
           (report (%write-report sample-size success success-rate threshold)))
      (format t "[SC-002] total=~d success=~d rate=~,2f%% threshold=~,2f%% report=~a~%"
              sample-size success success-rate threshold report)
      (when (< success-rate threshold)
        (error "SC-002 failed: success rate ~,2f%% below threshold ~,2f%%" success-rate threshold))
      t)))

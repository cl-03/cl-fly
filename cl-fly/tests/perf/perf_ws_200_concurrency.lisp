(defpackage #:cl-fly.tests.perf.sc001
  (:use #:cl)
  (:export #:run-sc001-gate
           #:run-sc001-baseline))

(in-package #:cl-fly.tests.perf.sc001)

(defun %env (name default)
  (or (uiop:getenv name) default))

(defun %env-int (name default)
  (parse-integer (%env name (princ-to-string default)) :junk-allowed t))

(defun %elapsed-ms (start end)
  (round (* 1000.0 (/ (- end start) internal-time-units-per-second))))

(defun %p95 (values)
  (let* ((ordered (sort (copy-list values) #'<))
         (n (length ordered))
         (idx (max 0 (1- (ceiling (* 0.95 n))))))
    (nth idx ordered)))

(defun %write-report (total success p95 threshold)
  (let* ((dir #p"d:/VSCode/project/cl-fly/tests/perf/reports/")
         (path (merge-pathnames "sc001-latest.txt" dir)))
    (ensure-directories-exist dir)
    (with-open-file (out path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (format out "scenario=sc001~%")
      (format out "total=~d~%" total)
      (format out "success=~d~%" success)
      (format out "p95_ms=~d~%" p95)
      (format out "threshold_ms=~d~%" threshold)
      (format out "generated_at_unix=~d~%" (get-universal-time)))
    path))

(defun %write-baseline-report (samples concurrency threshold records)
  (let* ((dir #p"d:/VSCode/project/cl-fly/tests/perf/reports/")
         (path (merge-pathnames "sc001-baseline-latest.txt" dir))
         (p95-list (mapcar (lambda (item) (getf item :p95)) records))
         (ordered (sort (copy-list p95-list) #'<))
         (avg (if ordered
                  (/ (reduce #'+ ordered) (length ordered))
                  0))
         (min-p95 (if ordered (first ordered) 0))
         (max-p95 (if ordered (car (last ordered)) 0)))
    (ensure-directories-exist dir)
    (with-open-file (out path :direction :output :if-exists :supersede :if-does-not-exist :create)
      (format out "scenario=sc001-baseline~%")
      (format out "samples=~d~%" samples)
      (format out "concurrency=~d~%" concurrency)
      (format out "threshold_ms=~d~%" threshold)
      (format out "avg_p95_ms=~,2f~%" avg)
      (format out "min_p95_ms=~d~%" min-p95)
      (format out "max_p95_ms=~d~%" max-p95)
      (loop for rec in records
            for idx from 1
            do (format out "sample_~d_total=~d~%" idx (getf rec :total))
               (format out "sample_~d_success=~d~%" idx (getf rec :success))
               (format out "sample_~d_p95_ms=~d~%" idx (getf rec :p95)))
      (format out "generated_at_unix=~d~%" (get-universal-time)))
    path))

(defun %run-sc001-once (concurrency threshold-ms)
  (let ((latencies '())
        (success 0)
        (lock (bt:make-lock "sc001-lock"))
        (threads '()))
    (dotimes (i concurrency)
      (push
       (bt:make-thread
        (lambda ()
          (let* ((client-id (format nil "perf-visitor-~d" i))
                 (sid (format nil "perf-session-~d" i))
                 (start (get-internal-real-time))
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
                                  :clientMsgId (format nil "c-~d" i))))
                 (finish (get-internal-real-time))
                 (ok (and (string= "session.ready" (getf init-res :event))
                          (string= "ack" (getf send-res :event)))))
            (bt:with-lock-held (lock)
              (push (%elapsed-ms start finish) latencies)
              (when ok
                (incf success)))))
        :name (format nil "sc001-~d" i))
       threads))
    (dolist (th threads)
      (bt:join-thread th))
    (let ((p95 (%p95 latencies)))
      (list :total concurrency
            :success success
            :p95 p95
            :threshold threshold-ms))))

(defun run-sc001-gate ()
  "T063: assert p95 latency gate under 200 concurrent logical sessions."
  (let* ((concurrency (%env-int "KEFU_SC001_CONCURRENCY" 200))
         (threshold-ms (%env-int "KEFU_SC001_P95_MS" 1000))
         (result (%run-sc001-once concurrency threshold-ms))
         (success (getf result :success))
         (p95 (getf result :p95))
         (total (getf result :total))
           (report (%write-report concurrency success p95 threshold-ms)))
      (format t "[SC-001] total=~d success=~d p95=~dms threshold=~dms report=~a~%"
              total success p95 threshold-ms report)
      (when (< success total)
        (error "SC-001 failed: success count ~d / ~d" success total))
      (when (> p95 threshold-ms)
        (error "SC-001 failed: p95 ~dms exceeds threshold ~dms" p95 threshold-ms))
      t))

(defun run-sc001-baseline ()
  "T055: collect baseline performance samples for 200-concurrency scenario."
  (let* ((concurrency (%env-int "KEFU_SC001_CONCURRENCY" 200))
         (threshold-ms (%env-int "KEFU_SC001_P95_MS" 1000))
         (samples (%env-int "KEFU_SC001_BASELINE_SAMPLES" 3))
         (records '()))
    (dotimes (idx samples)
      (let ((result (%run-sc001-once concurrency threshold-ms)))
        (push result records)
        (format t "[SC-001-BASELINE] sample=~d/~d total=~d success=~d p95=~dms~%"
                (1+ idx)
                samples
                (getf result :total)
                (getf result :success)
                (getf result :p95))))
    (let* ((ordered (nreverse records))
           (report (%write-baseline-report samples concurrency threshold-ms ordered)))
      (format t "[SC-001-BASELINE] samples=~d concurrency=~d report=~a~%"
              samples concurrency report)
      t)))

(defpackage #:cl-fly.tests.integration.quickstart-smoke
  (:use #:cl)
  (:export #:run-quickstart-smoke-tests))

(in-package #:cl-fly.tests.integration.quickstart-smoke)

(defun %env (name default)
  (or (uiop:getenv name) default))

(defun %env-int (name default)
  (parse-integer (%env name (princ-to-string default)) :junk-allowed t))

(defun %read-line-crlf (stream)
  (let ((line (read-line stream nil nil)))
    (and line (string-right-trim '(#\Return #\Newline) line))))

(defun %http-status-line (host port path)
  (let* ((socket (usocket:socket-connect host port :element-type 'character))
         (stream (usocket:socket-stream socket))
         (request (format nil "GET ~a HTTP/1.1~c~cHost: ~a~c~cConnection: close~c~c~c~c"
                          path #\Return #\Linefeed host #\Return #\Linefeed #\Return #\Linefeed #\Return #\Linefeed)))
    (unwind-protect
         (progn
           (write-string request stream)
           (finish-output stream)
           (%read-line-crlf stream))
      (ignore-errors (close stream))
      (ignore-errors (usocket:socket-close socket)))))

(defun %ws-handshake-status-line (host port path)
  (let* ((socket (usocket:socket-connect host port :element-type 'character))
         (stream (usocket:socket-stream socket))
         (request (format nil
                          "GET ~a HTTP/1.1~c~cHost: ~a~c~cUpgrade: websocket~c~cConnection: Upgrade~c~cSec-WebSocket-Version: 13~c~cSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==~c~c~c~c"
                          path
                          #\Return #\Linefeed
                          host
                          #\Return #\Linefeed
                          #\Return #\Linefeed
                          #\Return #\Linefeed
                          #\Return #\Linefeed
                          #\Return #\Linefeed
                          #\Return #\Linefeed)))
    (unwind-protect
         (progn
           (write-string request stream)
           (finish-output stream)
           (%read-line-crlf stream))
      (ignore-errors (close stream))
      (ignore-errors (usocket:socket-close socket)))))

(defun %assert-contains (text needle)
  (unless (and text (search needle text))
    (error "Assertion failed: expected ~s to contain ~s" text needle)))

(defun %status-code (status-line)
  (let ((first-space (and status-line (position #\Space status-line))))
    (when first-space
      (let ((second-space (position #\Space status-line :start (1+ first-space))))
        (when second-space
          (subseq status-line (1+ first-space) second-space))))))

(defun %assert-status-code (status-line expected)
  (let ((actual (%status-code status-line)))
    (unless (and actual (string= actual expected))
      (error "Assertion failed: expected status ~a, got line ~s" expected status-line))))

(defun %port-open-p (host port)
  (handler-case
      (let ((socket (usocket:socket-connect host port :element-type 'character)))
        (unwind-protect
             t
          (ignore-errors (usocket:socket-close socket))))
    (error () nil)))

(defun %find-open-port-pair (host candidates)
  (loop for (http-port ws-port) in candidates
        when (and (%port-open-p host http-port)
                  (%port-open-p host ws-port))
          do (return (list http-port ws-port))
        finally (return nil)))

(defun run-quickstart-smoke-tests ()
  "T062: smoke-check /health and websocket handshakes through deployment entrypoint."
  (let* ((host (%env "KEFU_GATE_HOST" "127.0.0.1"))
         ;; Prefer explicit gate ports, then app runtime ports, then local runtime defaults.
         (http-port (%env-int "KEFU_GATE_HTTP_PORT" (%env-int "KEFU_HTTP_PORT" 4000)))
   (ws-port (%env-int "KEFU_GATE_WS_PORT" (%env-int "KEFU_WS_PORT" 4001)))
   (started-local nil)
         (open-pair nil)
   (health-status nil)
   (visitor-ws-status nil)
   (agent-ws-status nil))
    (unwind-protect
   (progn
           (setf open-pair
                 (%find-open-port-pair host
                                       (remove-duplicates
                                        (list (list http-port ws-port)
                                              (list 4000 4001)
                                              (list 8081 8082)
                                              (list 80 80))
                                        :test #'equal)))
           (if open-pair
               (progn
                 (setf http-port (first open-pair))
                 (setf ws-port (second open-pair)))
               (progn
                 (setf started-local t)
                 (let ((app-info (cl-fly.app:start)))
                   (setf http-port (or (getf app-info :port) http-port))
                   (setf ws-port (or (getf app-info :ws-port) ws-port)))
                 (sleep 1)))
     (setf health-status (%http-status-line host http-port "/health"))
     (setf visitor-ws-status (%ws-handshake-status-line host ws-port "/ws/visitor"))
     (setf agent-ws-status (%ws-handshake-status-line host ws-port "/ws/agent"))
     (%assert-status-code health-status "200")
     (%assert-status-code visitor-ws-status "101")
     (%assert-status-code agent-ws-status "101")
     (format t "[PASS] quickstart smoke: health=~a visitor=~a agent=~a~%"
       health-status visitor-ws-status agent-ws-status)
     t)
      (when started-local
  (ignore-errors (cl-fly.api.http:stop-http-server))
  (ignore-errors (cl-fly.infra.ws-server:stop-ws-server))))))

(defpackage #:cl-fly.tests.integration.http-agent-sender-auth
  (:use #:cl #:fiveam)
  (:import-from #:cl-fly.api.http
                #:start-http-server
                #:stop-http-server)
  (:import-from #:cl-fly.auth.jwt
                #:issue-token)
  (:export #:run-http-agent-sender-auth-integration-tests))

(in-package #:cl-fly.tests.integration.http-agent-sender-auth)

(def-suite http-agent-sender-auth-integration-suite
  :description "Integration checks for HTTP agent sender auth guard on /api/v1/messages.")

(in-suite http-agent-sender-auth-integration-suite)

(defun %read-line-crlf (stream)
  (let ((line (read-line stream nil nil)))
    (and line (string-right-trim '(#\Return #\Newline) line))))

(defun %post-messages-status-line (&key auth-token)
  (let* ((host "127.0.0.1")
         (port 4000)
         (body "{\"sessionId\":\"auth-guard-s1\",\"senderType\":\"agent\",\"messageType\":\"text\",\"content\":\"hello\"}")
         (auth-header (if auth-token
                          (format nil "Authorization: Bearer ~a~c~c" auth-token #\Return #\Linefeed)
                          ""))
         (request (with-output-to-string (out)
                    (format out "POST /api/v1/messages HTTP/1.1~c~c" #\Return #\Linefeed)
                    (format out "Host: ~a~c~c" host #\Return #\Linefeed)
                    (format out "Content-Type: application/json~c~c" #\Return #\Linefeed)
                    (format out "Content-Length: ~d~c~c" (length body) #\Return #\Linefeed)
                    (when auth-token
                      (write-string auth-header out))
                    (format out "Connection: close~c~c~c~c" #\Return #\Linefeed #\Return #\Linefeed)
                    (write-string body out)))
         (socket (usocket:socket-connect host port :element-type 'character))
         (stream (usocket:socket-stream socket)))
    (unwind-protect
         (progn
           (write-string request stream)
           (finish-output stream)
           (%read-line-crlf stream))
      (ignore-errors (close stream))
      (ignore-errors (usocket:socket-close socket)))))

(defun %post-upload-status-line (&key auth-token uploader-id)
  (let* ((host "127.0.0.1")
         (port 4000)
         (body (format nil "{\"sessionId\":\"auth-upload-s1\",\"senderType\":\"agent\",\"uploaderId\":\"~a\",\"fileName\":\"ok.txt\",\"fileContent\":\"hello\",\"mimeType\":\"text/plain\",\"fileSize\":5}" (or uploader-id "")))
         (auth-header (if auth-token
                          (format nil "Authorization: Bearer ~a~c~c" auth-token #\Return #\Linefeed)
                          ""))
         (request (with-output-to-string (out)
                    (format out "POST /api/v1/files/upload HTTP/1.1~c~c" #\Return #\Linefeed)
                    (format out "Host: ~a~c~c" host #\Return #\Linefeed)
                    (format out "Content-Type: application/json~c~c" #\Return #\Linefeed)
                    (format out "Content-Length: ~d~c~c" (length body) #\Return #\Linefeed)
                    (when auth-token
                      (write-string auth-header out))
                    (format out "Connection: close~c~c~c~c" #\Return #\Linefeed #\Return #\Linefeed)
                    (write-string body out)))
         (socket (usocket:socket-connect host port :element-type 'character))
         (stream (usocket:socket-stream socket)))
    (unwind-protect
         (progn
           (write-string request stream)
           (finish-output stream)
           (%read-line-crlf stream))
      (ignore-errors (close stream))
      (ignore-errors (usocket:socket-close socket)))))

(defun %status-code (status-line)
  (let ((first-space (and status-line (position #\Space status-line))))
    (when first-space
      (let ((second-space (position #\Space status-line :start (1+ first-space))))
        (when second-space
          (subseq status-line (1+ first-space) second-space))))))

(defmacro with-http-running (&body body)
  `(unwind-protect
       (progn
         (start-http-server)
         ,@body)
     (ignore-errors (stop-http-server))))

(test agent-sender-auth-matrix
  (with-http-running
    (let ((status (%post-messages-status-line)))
      (is (string= "401" (%status-code status))))
    (let* ((visitor-token (issue-token "visitor-1" :role "visitor" :ttl-seconds 60))
           (status (%post-messages-status-line :auth-token visitor-token)))
      (is (string= "401" (%status-code status))))
    (let* ((agent-token (issue-token "agent-1" :role "agent" :ttl-seconds 60))
           (status (%post-messages-status-line :auth-token agent-token)))
      (is (string= "201" (%status-code status))))))

(test upload-audit-actor-derived-from-token-sub
  (let ((original-write-audit (symbol-function 'cl-fly.core.audit:write-audit-event))
        (captured nil))
    (unwind-protect
         (progn
           (setf (symbol-function 'cl-fly.core.audit:write-audit-event)
                 (lambda (actor action target-type target-id details)
                   (setf captured (list :actor actor
                                        :action action
                                        :target-type target-type
                                        :target-id target-id
                                        :details details))
                   nil))
           (with-http-running
             (let* ((agent-token (issue-token "agent-sub-900" :role "agent" :ttl-seconds 60))
                    (status (%post-upload-status-line :auth-token agent-token :uploader-id "spoofed-agent")))
               (is (string= "201" (%status-code status)))
               (is (string= "agent-sub-900" (getf captured :actor)))
               (is (string= "attachment.upload" (getf captured :action))))))
      (setf (symbol-function 'cl-fly.core.audit:write-audit-event) original-write-audit))))

(defun run-http-agent-sender-auth-integration-tests ()
  (run! 'http-agent-sender-auth-integration-suite))

(in-package #:cl-fly.infra.ws-server)

(defparameter *ws-listener* nil)
(defparameter *ws-accept-thread* nil)
(defparameter *ws-running* nil)
(defparameter *ws-clients* (make-hash-table :test 'equal))

(defun %random-client-id (prefix)
  (format nil "~a-~a-~a" prefix (get-universal-time) (random 1000000)))

(defun %string-trim-crlf (s)
  (string-trim '(#\Return #\Newline #\Space #\Tab) s))

(defun %read-http-line (stream)
  (let ((buf (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (loop for b = (read-byte stream nil nil)
          do (cond
               ((null b)
                (return (if (> (length buf) 0)
                            (babel:octets-to-string buf :encoding :utf-8)
                            nil)))
               ((= b 10)
                (return (babel:octets-to-string buf :encoding :utf-8)))
               ((/= b 13)
                (vector-push-extend b buf))))))

(defun %read-http-request (stream)
  (let ((request-line (%read-http-line stream)))
    (when (and request-line (> (length (%string-trim-crlf request-line)) 0))
      (let* ((parts (uiop:split-string (%string-trim-crlf request-line) :separator '(#\Space)))
             (method (first parts))
             (path (second parts))
             (headers '()))
        (loop for line = (%read-http-line stream)
              while line
              for clean = (%string-trim-crlf line)
              do (if (string= clean "")
                     (return)
                     (let ((pos (position #\: clean)))
                       (when pos
                         (let ((k (string-downcase (subseq clean 0 pos)))
                               (v (%string-trim-crlf (subseq clean (1+ pos)))))
                           (push (cons k v) headers))))))
        (list :method method :path path :headers headers)))))

(defun %header (headers name)
  (cdr (assoc (string-downcase name) headers :test #'string=)))

(defun %ws-accept-value (client-key)
  (let* ((raw (concatenate 'string client-key "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
         (digest (ironclad:digest-sequence :sha1 (babel:string-to-octets raw :encoding :utf-8))))
    (cl-base64:usb8-array-to-base64-string digest)))

(defun %write-http-bytes (stream text)
  (write-sequence (babel:string-to-octets text :encoding :utf-8) stream)
  (finish-output stream))

(defun %send-handshake-ok (stream accept-value)
  (%write-http-bytes
   stream
   (format nil
           "HTTP/1.1 101 Switching Protocols~c~cUpgrade: websocket~c~cConnection: Upgrade~c~cSec-WebSocket-Accept: ~a~c~c~c~c"
           #\Return #\Linefeed #\Return #\Linefeed #\Return #\Linefeed accept-value #\Return #\Linefeed #\Return #\Linefeed)))

(defun %send-http-error (stream code message)
  (%write-http-bytes
   stream
   (format nil
           "HTTP/1.1 ~a ~a~c~cContent-Type: text/plain~c~cContent-Length: ~d~c~c~c~c~a"
           code message
           #\Return #\Linefeed #\Return #\Linefeed
           (length message)
           #\Return #\Linefeed #\Return #\Linefeed
           message)))

(defun %read-n-bytes (stream n)
  (let ((buf (make-array n :element-type '(unsigned-byte 8))))
    (read-sequence buf stream)
    buf))

(defun %read-u16 (stream)
  (+ (ash (read-byte stream) 8)
     (read-byte stream)))

(defun %read-u64 (stream)
  (let ((n 0))
    (dotimes (_ 8 n)
      (setf n (+ (ash n 8) (read-byte stream))))))

(defun %write-u16 (stream n)
  (write-byte (ldb (byte 8 8) n) stream)
  (write-byte (ldb (byte 8 0) n) stream))

(defun %write-u64 (stream n)
  (dotimes (i 8)
    (write-byte (ldb (byte 8 (* 8 (- 7 i))) n) stream)))

(defun %decode-frame (stream)
  (let ((b1 (read-byte stream nil nil))
        (b2 (read-byte stream nil nil)))
    (when (and b1 b2)
      (let* ((opcode (logand b1 #x0F))
             (masked (not (zerop (logand b2 #x80))))
             (len7 (logand b2 #x7F))
             (len (cond
                    ((< len7 126) len7)
                    ((= len7 126) (%read-u16 stream))
                    (t (%read-u64 stream))))
             (mask (when masked (%read-n-bytes stream 4)))
             (payload (%read-n-bytes stream len)))
        (when masked
          (dotimes (i len)
            (setf (aref payload i)
                  (logxor (aref payload i) (aref mask (mod i 4))))))
        (list :opcode opcode :payload payload)))))

(defun %encode-text-frame (text)
  (let* ((payload (babel:string-to-octets text :encoding :utf-8))
         (len (length payload))
         (buf (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (vector-push-extend #x81 buf)
    (cond
      ((< len 126)
       (vector-push-extend len buf))
      ((< len 65536)
       (vector-push-extend 126 buf)
       (vector-push-extend (ldb (byte 8 8) len) buf)
       (vector-push-extend (ldb (byte 8 0) len) buf))
      (t
       (vector-push-extend 127 buf)
       (dotimes (i 8)
         (vector-push-extend (ldb (byte 8 (* 8 (- 7 i))) len) buf))))
    (dotimes (i len)
      (vector-push-extend (aref payload i) buf))
    buf))

(defun %send-text (stream text)
  (write-sequence (%encode-text-frame text) stream)
  (finish-output stream))

(defun %send-pong (stream payload)
  (let ((len (length payload)))
    (write-byte #x8A stream)
    (cond
      ((< len 126)
       (write-byte len stream))
      ((< len 65536)
       (write-byte 126 stream)
       (%write-u16 stream len))
      (t
       (write-byte 127 stream)
       (%write-u64 stream len)))
    (write-sequence payload stream)
    (finish-output stream)))

(defun %send-close (stream)
  (write-byte #x88 stream)
  (write-byte 0 stream)
  (finish-output stream))

(defun %dispatch-handler (path)
  (cond
    ((string= path "/ws/visitor") #'cl-fly.api.ws-visitor:handle-visitor-event)
    ((string= path "/ws/agent") #'cl-fly.api.ws-agent:handle-agent-event)
    (t nil)))

(defun %safe-parse-json (text)
  (handler-case
      (jonathan:parse text :as :plist)
    (error () nil)))

(defun %handle-ws-session (socket stream handler path)
  (let ((client-id (%random-client-id (if (string= path "/ws/agent") "agent" "visitor"))))
    (setf (gethash client-id *ws-clients*) socket)
    (unwind-protect
         (loop for frame = (%decode-frame stream)
               while frame
               do (let ((opcode (getf frame :opcode))
                        (payload (getf frame :payload)))
                    (cond
                      ((= opcode #x1)
                       (let* ((text (babel:octets-to-string payload :encoding :utf-8))
                              (data (%safe-parse-json text))
                              (event (or (loop for (k v) on data by #'cddr
                                               when (string-equal (string k) "event") do (return v))
                                         ""))
                              (event-payload (or (loop for (k v) on data by #'cddr
                                                       when (string-equal (string k) "payload") do (return v))
                                                 nil))
                              (response (funcall handler client-id event event-payload)))
                         (%send-text stream (jonathan:to-json response))))
                      ((= opcode #x8)
                       (return))
                      ((= opcode #x9)
                       (%send-pong stream payload))
                      (t nil))))
      (ignore-errors
        (cl-fly.api.ws-common:unregister-client client-id)
        (remhash client-id *ws-clients*)
        (%send-close stream)
        (usocket:socket-close socket)))))

(defun %handle-client (socket)
  (let ((stream (usocket:socket-stream socket)))
    (handler-case
        (let* ((request (%read-http-request stream)))
          (if (null request)
              (%send-http-error stream 400 "Bad Request")
              (let* ((path (getf request :path))
                     (headers (getf request :headers))
                     (key (%header headers "sec-websocket-key"))
                     (handler (%dispatch-handler path)))
                (cond
                  ((null handler)
                   (%send-http-error stream 404 "Not Found"))
                  ((or (null key) (string= key ""))
                   (%send-http-error stream 400 "Missing Sec-WebSocket-Key"))
                  (t
                   (%send-handshake-ok stream (%ws-accept-value key))
                   (log-info "websocket handshake accepted" (list :path path))
                   (%handle-ws-session socket stream handler path))))))
      (error (e)
        (log-error "websocket client failure" (list :error (princ-to-string e)))
        (ignore-errors (usocket:socket-close socket))))))

(defun %accept-loop ()
  (loop while *ws-running*
        do (handler-case
               (let ((client (usocket:socket-accept *ws-listener* :element-type '(unsigned-byte 8))))
                 (bt:make-thread
                  (lambda ()
                    ;; Defensive guard: keep client-thread failures from bubbling as unhandled
                    ;; conditions that can poison test runner exit status.
                    (handler-case
                        (%handle-client client)
                      (serious-condition (e)
                        (log-error "websocket client thread crashed"
                                   (list :error (princ-to-string e)))
                        (ignore-errors (usocket:socket-close client)))))
                                 :name "cl-fly-ws-client"))
             (error (e)
               (when *ws-running*
                 (log-warn "websocket accept loop error" (list :error (princ-to-string e))))))))

(defun start-ws-server ()
  (unless *ws-running*
    (let ((port (config-get :ws-port 4001)))
      (setf *ws-listener* (usocket:socket-listen "0.0.0.0" port :reuse-address t :element-type '(unsigned-byte 8)))
      (setf *ws-running* t)
      (setf *ws-accept-thread* (bt:make-thread #'%accept-loop :name "cl-fly-ws-accept"))
      (log-info "WebSocket server started" (list :port port))))
  t)

(defun stop-ws-server ()
  (setf *ws-running* nil)
  (when *ws-listener*
    (ignore-errors (usocket:socket-close *ws-listener*))
    (setf *ws-listener* nil))
  t)

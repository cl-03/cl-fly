(in-package #:cl-fly.api.error)

(define-condition http-error (error)
  ((status :initarg :status :reader http-error-status)
   (code :initarg :code :reader http-error-code)
   (message :initarg :message :reader http-error-message)))

(defun make-http-error (status code message)
  (make-condition 'http-error
                  :status status
                  :code code
                  :message message))

(defun error->response (err)
  "Convert an HTTP error condition to a JSON-ready plist."
  (list :status (http-error-status err)
        :body (list :ok nil
                    :error (list :code (http-error-code err)
                                 :message (http-error-message err)))))

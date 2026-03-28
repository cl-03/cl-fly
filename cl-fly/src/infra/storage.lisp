(in-package #:cl-fly.infra.storage)

(defparameter *allowed-file-extensions*
  '("png" "jpg" "jpeg" "gif" "pdf" "txt" "zip"))

(defparameter *max-upload-size-bytes* (* 10 1024 1024))

(defun %extension-of (filename)
  (let ((dot (position #\. filename :from-end t)))
    (if dot
        (string-downcase (subseq filename (1+ dot)))
        "")))

(defun sanitize-filename (filename)
  (let ((safe (copy-seq filename)))
    (dotimes (i (length safe))
      (let ((ch (aref safe i)))
        (when (or (char= ch #\\) (char= ch #\/)
                  (char= ch #\:) (char= ch #\*)
                  (char= ch #\?) (char= ch #\")
                  (char= ch #\<) (char= ch #\>)
                  (char= ch #\|))
          (setf (aref safe i) #\_))))
    safe))

(defun allowed-file-type-p (filename)
  (member (%extension-of filename) *allowed-file-extensions* :test #'string=))

(defun valid-file-size-p (size-bytes)
  (and (integerp size-bytes)
       (>= size-bytes 0)
       (<= size-bytes *max-upload-size-bytes*)))

(defun validate-upload (filename size-bytes)
  (cond
    ((not (allowed-file-type-p filename))
     (list :ok nil :code "UNSUPPORTED_FILE_TYPE" :message "unsupported file type"))
    ((not (valid-file-size-p size-bytes))
     (list :ok nil :code "FILE_TOO_LARGE" :message "file exceeds size limit"))
    (t
     (list :ok t))))

(defun %ensure-upload-dir (session-id)
  (let ((dir (merge-pathnames
              (make-pathname :directory `(:relative "uploads" ,session-id))
              #p"d:/VSCode/project/cl-fly/")))
    (ensure-directories-exist dir)
    dir))

(defun store-file-local (session-id filename content)
  (let* ((safe-name (sanitize-filename filename))
         (dir (%ensure-upload-dir session-id))
         (key (get-universal-time))
         (stored-name (format nil "~a_~a" key safe-name))
         (file-path (merge-pathnames stored-name dir)))
    (with-open-file (out file-path
                         :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create)
      (write-string (or content "") out))
    (namestring file-path)))

(defun delete-stored-file (file-path)
  (when (and file-path (probe-file file-path))
    (delete-file file-path))
  t)

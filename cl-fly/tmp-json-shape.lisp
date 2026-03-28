(require :asdf)
(unless (find-package :ql)
     (let ((setup (or (uiop:getenv "QUICKLISP_SETUP")
                                              "c:/Users/Administrator/quicklisp/setup.lisp"
                                              "d:/VSCode/project/quicklisp/setup.lisp")))
          (when (and setup (probe-file setup))
               (load setup))))
(asdf:load-system :jonathan)
(let* ((entry (list :message-id "m-1"
                    :session-id "s-1"
                    :sender-type "visitor"
                    :message-type "text"
                    :content "hello"
                    :created-at 123))
       (payload (list :ok t :sessionId "s-1" :messages (list entry))))
  (format t "~a~%" (jonathan:to-json payload)))

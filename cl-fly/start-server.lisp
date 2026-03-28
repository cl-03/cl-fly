(require :asdf)
(load "c:/Users/Administrator/quicklisp/setup.lisp")
(ql:quickload '("hunchentoot"
                "jonathan"
                "local-time"
                "postmodern"
                "usocket"
                "bordeaux-threads"
                "ironclad"
                "cl-base64"
                "babel"))
(asdf:load-asd #p"d:/VSCode/project/cl-fly/cl-fly.asd")
(asdf:load-system "cl-fly")
(cl-fly.app:start)

;; Keep the process alive when launched via --script.
(loop
    (sleep 3600))
(loop (sleep 3600))

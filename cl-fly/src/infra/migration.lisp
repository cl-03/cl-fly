(defpackage #:cl-fly.migration
  (:use #:cl)
  (:import-from #:cl-fly.infra.db
                #:with-db)
  (:export #:up))

(in-package #:cl-fly.migration)

(defun %migration-path ()
  (let* ((current (or *load-truename* *default-pathname-defaults*))
         (infra-dir (uiop:pathname-parent-directory-pathname current))
         (src-dir (uiop:pathname-parent-directory-pathname infra-dir))
         (project-root (uiop:pathname-parent-directory-pathname src-dir)))
    (merge-pathnames "migrations/001_init.sql" project-root)))

(defun %split-sql (sql)
  (remove-if (lambda (s) (string= "" (string-trim '(#\Space #\Tab #\Newline #\Return) s)))
             (uiop:split-string sql :separator '(#\;))))

(defun up ()
  "Apply the initial SQL migration script."
  (let* ((sql (uiop:read-file-string (%migration-path)))
         (stmts (%split-sql sql)))
    (with-db ()
      (dolist (stmt stmts)
        (postmodern:execute stmt))))
  t)

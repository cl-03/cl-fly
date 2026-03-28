(require :asdf)

(defparameter *cl-fly-required-systems*
	'("fiveam"
		"hunchentoot"
		"jonathan"
		"local-time"
		"postmodern"
		"usocket"
		"bordeaux-threads"
		"ironclad"
		"cl-base64"
		"babel"))

(defun %find-quicklisp-setup ()
	(or (uiop:getenv "QUICKLISP_SETUP")
		"c:/Users/Administrator/quicklisp/setup.lisp"
		"d:/VSCode/project/quicklisp/setup.lisp"))

(defun %ensure-quicklisp-loaded ()
	(unless (find-package :ql)
	  (let ((setup (%find-quicklisp-setup)))
		(if (and setup (probe-file setup))
			(load setup)
			(error "Quicklisp not found. Set QUICKLISP_SETUP or install quicklisp/setup.lisp.")))))

(defun %bootstrap-dependencies ()
	;; Auto-install/load all required systems via Quicklisp for local/dev environments.
	(format t "Bootstrapping dependencies...~%")
	(%ensure-quicklisp-loaded)
	(let* ((ql-pkg (find-package :ql))
		   (quickload (and ql-pkg (find-symbol "QUICKLOAD" ql-pkg))))
	  (unless quickload
		(error "Quicklisp is loaded but QL:QUICKLOAD is unavailable."))
	  (funcall quickload *cl-fly-required-systems*))
	(asdf:load-asd #p"d:/VSCode/project/cl-fly/cl-fly.asd")
	(asdf:load-system "cl-fly"))

(%bootstrap-dependencies)

(load #p"d:/VSCode/project/cl-fly/tests/contract/test_sessions_api.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/contract/test_messages_api.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/contract/test_auth_login.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/contract/test_session_transfer.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/contract/test_config_api.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/contract/test_stats_api.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/contract/test_file_upload_api.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/contract/test_p1_macro_attributes_api.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/integration/test_ws_visitor_flow.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/integration/test_ws_agent_flow.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/integration/test_transfer_flow.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/integration/test_blacklist_flow.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/integration/test_attachment_message_flow.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/integration/test_quickstart_smoke.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/unit/test_upload_policy.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/perf/perf_ws_200_concurrency.lisp")
(load #p"d:/VSCode/project/cl-fly/tests/perf/perf_first_message_success_rate.lisp")

(format t "Running cl-fly tests...~%")


(handler-case
	(let ((release-gates-p (string= (or (uiop:getenv "KEFU_ENABLE_RELEASE_GATES") "0") "1")))
	  (cl-fly.tests.contract.sessions:run-sessions-contract-tests)
	  (cl-fly.tests.contract.messages:run-messages-contract-tests)
	  (cl-fly.tests.contract.auth-login:run-auth-login-contract-tests)
	  (cl-fly.tests.contract.session-transfer:run-session-transfer-contract-tests)
	  (cl-fly.tests.contract.config-api:run-config-api-contract-tests)
	  (cl-fly.tests.contract.stats-api:run-stats-api-contract-tests)
	  (cl-fly.tests.contract.file-upload-api:run-file-upload-api-contract-tests)
	  (cl-fly.tests.contract.p1-macro-attributes:run-p1-macro-attributes-contract-tests)
	  (cl-fly.tests.unit.upload-policy:run-upload-policy-unit-tests)
	  (cl-fly.tests.integration.ws-visitor:run-ws-visitor-integration-tests)
	  (cl-fly.tests.integration.ws-agent:run-ws-agent-integration-tests)
	  (cl-fly.tests.integration.transfer-flow:run-transfer-flow-integration-tests)
	  (cl-fly.tests.integration.blacklist-flow:run-blacklist-flow-integration-tests)
	  (cl-fly.tests.integration.attachment-message-flow:run-attachment-message-flow-integration-tests)

	  ;; T063/T064 are always executed as quality gates.
	  (cl-fly.tests.perf.sc001:run-sc001-gate)
	  (cl-fly.tests.perf.sc002:run-sc002-gate)

	  ;; T055 baseline sampling is opt-in to keep default CI runtime stable.
	  (when (string= (or (uiop:getenv "KEFU_ENABLE_PERF_BASELINE") "0") "1")
		(cl-fly.tests.perf.sc001:run-sc001-baseline))

	  ;; T062 requires deployed entrypoint (typically Nginx), so keep it opt-in.
	  (if release-gates-p
		  (cl-fly.tests.integration.quickstart-smoke:run-quickstart-smoke-tests)
		  (format t "[SKIP] quickstart smoke gate (set KEFU_ENABLE_RELEASE_GATES=1 to enable).~%"))

	  (format t "All requested test suites executed.~%")
	  (uiop:quit 0))
  (error (e)
	(format *error-output* "[FAIL] ~a~%" e)
	(uiop:quit 1)))

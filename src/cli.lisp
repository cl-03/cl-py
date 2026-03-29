(in-package #:cl-py)

(defun %print-registry ()
  (dolist (adapter (list-adapters))
    (format t "~A~%" (adapter-id adapter))
    (format t "  manifest-version: ~A~%" (adapter-manifest-version adapter))
    (format t "  name: ~A~%" (adapter-name adapter))
    (format t "  upstream-url: ~A~%" (adapter-upstream-url adapter))
    (format t "  license: ~A~%" (adapter-license adapter))
    (format t "  module: ~A~%" (adapter-python-module adapter))
    (format t "  distribution: ~A~%" (adapter-python-distribution adapter))
    (format t "  python-requirement: ~A~%" (adapter-python-requirement adapter))
    (format t "  capabilities: ~{~A~^, ~}~%" (adapter-capabilities adapter))
    (format t "  summary: ~A~%" (cl-py.internal:adapter-summary adapter))))

(defun %print-adapter-metadata (adapter-id)
  (let ((metadata (adapter-metadata adapter-id)))
    (format t "id: ~A~%" (getf metadata :id))
    (format t "manifest-version: ~A~%" (getf metadata :manifest-version))
    (format t "name: ~A~%" (getf metadata :name))
    (format t "upstream-url: ~A~%" (getf metadata :upstream-url))
    (format t "license: ~A~%" (getf metadata :license))
    (format t "python-module: ~A~%" (getf metadata :python-module))
    (format t "python-distribution: ~A~%" (getf metadata :python-distribution))
    (format t "python-requirement: ~A~%" (getf metadata :python-requirement))
    (format t "capabilities: ~{~A~^, ~}~%" (getf metadata :capabilities))
    (format t "summary: ~A~%" (getf metadata :summary))))

(defun %registry-command-handler (args)
  (if (null args)
      (%print-registry)
      (cl-py.internal:signal-cli-usage-error
       "registry does not accept positional arguments"
       #'%print-registry-usage)))

(defun %print-registry-usage ()
  (format t "Subcommands: none~%")
  (format t "This command prints the full manifest-backed adapter registry.~%"))

(defun main ()
  (handler-case
      (let ((args (uiop:command-line-arguments)))
        (if (null args)
            (cl-py.internal:print-cli-usage)
            (cl-py.internal:dispatch-top-level-command args)))
    (cli-usage-error (condition)
      (format *error-output* "~A~%" condition)
      (let ((*standard-output* *error-output*))
        (funcall (cli-usage-printer condition)))
      (uiop:quit 2))
    (adapter-error (condition)
      (format *error-output* "~A~%" condition)
      (uiop:quit 1))))

(cl-py.internal:register-top-level-cli-command
 "registry"
 #'%registry-command-handler
 :usage "registry"
 :summary "List registered adapters with manifest metadata"
 :detail-printer #'%print-registry-usage)

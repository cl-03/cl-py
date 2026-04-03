(in-package #:cl-py)

;;; ============================================================================
;;; 宏定义命令注册 - 借鉴 clingon 的 defcommand 设计
;;; ============================================================================

(defmacro define-cli-command (name args-list &body body)
  "Define a CLI command with automatic handler registration.

  Similar to clingon's defcommand, this macro creates a command handler function
  and provides a clean DSL for command definition.

  Example:
    (define-cli-command hello (name &key greeting)
      :usage \"hello <name> [--greeting TEXT]\"
      :summary \"Say hello to someone\"
      (format t \"~A, ~A!\" (or greeting \"Hello\") name))"
  (let ((handler-name (intern (format nil "%CLI-~A-HANDLER" (string-upcase name))
                              (symbol-package name)))
        (usage (getf (getf args-list '&key) :usage))
        (summary (getf (getf args-list '&key) :summary)))
    `(progn
       (defun ,handler-name (args)
         ,@body)
       (register-top-level-cli-command
        ,name
        #',handler-name
        :usage ,(or usage (format nil "~A [options]" name))
        :summary ,(or summary "")
        :detail-printer #',(or usage #'print-cli-usage)))))

(defmacro define-adapter-command (adapter-id name args-list &body body)
  "Define an adapter CLI command with automatic registration.

  Example:
    (define-adapter-command \"packaging\" normalize-version (version)
      :summary \"Normalize a version string\"
      (normalize-packaging-version version))"
  (let ((handler-name (intern (format nil "%ADAPTER-~A-~A-HANDLER"
                                      (string-upcase adapter-id)
                                      (string-upcase name))
                              (symbol-package name))))
    `(progn
       (defun ,handler-name (args)
         ,@body)
       (register-cli-command
        ,adapter-id
        ,name
        #',handler-name
        :summary ""
        :min-args 0))))

;;; ============================================================================
;;; 结构化输出 DSL - 借鉴 spinneret 的标签式输出设计
;;; ============================================================================

(defstruct output-buffer
  (stream nil)
  (indent 0))

(defmacro %with-output-buffer (&body body)
  "Execute body with an output buffer stream."
  `(with-output-to-string (stream)
     (let ((buf (make-output-buffer :stream stream)))
       ,@body)))

(defmacro with-yaml-output (&body body)
  "Generate YAML output using a spinneret-like DSL.

  Example:
    (with-yaml-output
      (yaml-object
        (yaml-key \"name\") (yaml-value \"cl-py\")
        (yaml-key \"active\") (yaml-value t)))"
  `(%with-output-buffer ,@body))

(defun yaml-object (&rest pairs)
  "Output a YAML object from key-value pairs."
  (format nil "~{~A: ~A~^~%~}"
          (loop for (k v) on pairs by #'cddr
                collect (format nil "~A~%" k)
                collect (format nil "~A" v))))

(defun yaml-sequence (&rest items)
  "Output a YAML sequence from items."
  (format nil "~{  - ~A~%~}" items))

;;; ============================================================================
;;; 声明式选项解析 - 借鉴 clingon 的选项定义 DSL
;;; ============================================================================

(defstruct cli-option
  "CLI option definition inspired by clingon's option DSL.

  Fields:
    name       - Long option name (e.g., \"--output\")
    short      - Short option name (e.g., \"-o\")
    dest       - Destination variable name
    help       - Help text
    metavar    - Value placeholder
    default    - Default value
    type       - Value type (:string, :integer, :boolean, :file)"
  name
  short
  dest
  help
  metavar
  default
  type)

;;; ============================================================================
;;; 增强的 Help 生成 - 从命令元数据自动生成结构化 Help
;;; ============================================================================

(defun %render-command-help (command)
  "Render structured help for a command from its metadata."
  (when (typep command 'top-level-cli-command)
    (format t "~%")
    (format t "NAME:~%")
    (format t "  ~A - ~A~%~%"
            (top-level-cli-command-name command)
            (top-level-cli-command-summary command))
    (format t "USAGE:~%")
    (format t "  ~A~%~%" (top-level-cli-command-usage command))
    (format t "OPTIONS:~%")
    (format t "  -h, --help     Show this help message~%")
    (format t "~%")))

(defun print-enhanced-help (command-name)
  "Print enhanced help for a command with structured sections."
  (let ((command (%find-top-level-cli-command command-name)))
    (if command
        (%render-command-help command)
        (print-command-help command-name))))

;;; ============================================================================
;;; Original CLI functions preserved below
;;; ============================================================================

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

;;; ============================================================================
;;; CLI Enhancements - Global flags for output control
;;; ============================================================================

(defvar *cli-output-file* nil
  "Global output file path for --output flag.")

(defvar *cli-quiet-p* nil
  "Global quiet mode flag for --quiet flag.")

(defun %parse-global-flags (args)
  "Parse global flags from command line arguments.
Returns (values remaining-args output-file quiet-p)."
  (let ((output-file nil)
        (quiet-p nil)
        (remaining nil))
    (loop for arg in args
          do (cond
               ((string= arg "--output")
                (setf output-file t))
               ((string= arg "--quiet")
                (setf quiet-p t))
               ((and output-file (eq output-file t))
                (setf output-file arg))
               ((and (string= (subseq arg 0 1) "-")
                     (not (string= arg "-")))
                ;; Unknown flag, skip
                nil)
               (t
                (push arg remaining))))
    (when (eq output-file t)
      (error "missing value for --output"))
    (values (nreverse remaining) output-file quiet-p)))

(defmacro %with-cli-output (&body body)
  "Execute body with CLI output redirection."
  `(let ((output-stream (if *cli-output-file*
                            (open *cli-output-file*
                                  :direction :output
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
                            *standard-output*)))
     (unwind-protect
          (let ((*standard-output* output-stream))
            ,@body)
       (when *cli-output-file*
         (close output-stream)))))

(defmacro define-cli-command-with-output ((name args-list &key usage summary) &body body)
  "Define a CLI command with automatic --output flag support.

  Example:
    (define-cli-command-with-output (hello (name &key greeting)
                              :usage \"hello <name>\"
                              :summary \"Say hello\")
      (format t \"Hello, ~A!\" name))"
  (let ((handler-name (intern (format nil "%CLI-~A-HANDLER" (string-upcase name))
                              (symbol-package name))))
    `(progn
       (defun ,handler-name (args)
         (let* ((values (%parse-global-flags args))
                (remaining (svref values 0))
                (output (svref values 1))
                (quiet (svref values 2)))
           (when output (setf *cli-output-file* output))
           (when quiet (setf *cli-quiet-p* quiet))
           (%with-cli-output
             (let ((,args-list remaining))
               ,@body))))
       (register-top-level-cli-command
        ,name
        #',handler-name
        :usage ,(or usage (format nil "~A [options]" name))
        :summary ,(or summary "")
        :detail-printer #',(or usage #'print-cli-usage)))))

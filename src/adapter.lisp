(in-package #:cl-py.internal)

(defstruct cli-command
  adapter-id
  name
  usage
  summary
  min-args
  handler)

(defstruct top-level-cli-command
  name
  usage
  summary
  handler
  detail-printer)

(defparameter *cli-command-registry* nil)
(defparameter *top-level-cli-command-registry* nil)

(defun help-flag-p (text)
  (member text '("help" "-h" "--help") :test #'string=))

(defun register-top-level-cli-command (name handler &key usage summary detail-printer)
  (let ((command (make-top-level-cli-command :name name
                                             :usage usage
                                             :summary summary
                                             :handler handler
                                             :detail-printer detail-printer)))
    (setf *top-level-cli-command-registry*
          (append (remove name *top-level-cli-command-registry*
                          :key #'top-level-cli-command-name
                          :test #'string=)
                  (list command)))
    command))

(defun register-cli-command (adapter-id name handler &key usage summary (min-args 0))
  (let ((command (make-cli-command :adapter-id adapter-id
                                   :name name
                                   :usage usage
                                   :summary summary
                                   :min-args min-args
                                   :handler handler)))
    (setf *cli-command-registry*
          (append (remove-if (lambda (existing)
                               (and (string= adapter-id (cli-command-adapter-id existing))
                                    (string= name (cli-command-name existing))))
                             *cli-command-registry*)
                  (list command)))
    command))

(defun %adapter-cli-commands (adapter-id)
  (remove-if-not (lambda (command)
                   (string= adapter-id (cli-command-adapter-id command)))
                 *cli-command-registry*))

(defun %find-cli-command (adapter-id name)
  (find-if (lambda (command)
             (and (string= adapter-id (cli-command-adapter-id command))
                  (string= name (cli-command-name command))))
           *cli-command-registry*))

(defun %find-top-level-cli-command (name)
  (find name *top-level-cli-command-registry*
        :key #'top-level-cli-command-name
        :test #'string=))

(defun %sorted-top-level-cli-commands ()
  (sort (copy-list *top-level-cli-command-registry*) #'string< :key #'top-level-cli-command-name))

(defun %sorted-adapter-cli-commands (adapter-id)
  (sort (copy-list (%adapter-cli-commands adapter-id)) #'string< :key #'cli-command-name))

(defun %sorted-adapters ()
  (sort (copy-list cl-py.internal:*adapter-registry*) #'string< :key #'adapter-id))

(defun %print-command-entry (usage summary &key (indent 2))
  (format t "~V@T~A~%" indent usage)
  (when summary
    (format t "~V@T~A~%" (+ indent 2) summary)))

(defun signal-cli-usage-error (message &optional (usage-printer #'print-cli-usage))
  (error 'cl-py:cli-usage-error :message message :usage-printer usage-printer))

(defun %adapter-usage-printer (adapter-id)
  (lambda ()
    (%print-adapter-command-usage (find-adapter-or-die adapter-id))))

(defun %print-adapter-command-usage (adapter)
  (format t "~A~%" (adapter-id adapter))
  (format t "  ~A~%" (adapter-summary adapter))
  (%print-command-entry (format nil "metadata") "Show adapter metadata" :indent 4)
  (%print-command-entry (format nil "version") "Show installed upstream version" :indent 4)
  (dolist (command (%sorted-adapter-cli-commands (adapter-id adapter)))
    (%print-command-entry (cli-command-usage command)
                          (cli-command-summary command)
                          :indent 4))
  (terpri))

(defun print-command-help (command-name)
  (let ((top-level-command (%find-top-level-cli-command command-name)))
    (cond
      (top-level-command
       (format t "Usage: ~A~%" (top-level-cli-command-usage top-level-command))
       (when (top-level-cli-command-summary top-level-command)
         (format t "~A~%~%" (top-level-cli-command-summary top-level-command)))
       (when (top-level-cli-command-detail-printer top-level-command)
         (funcall (top-level-cli-command-detail-printer top-level-command))))
      ((cl-py:find-adapter command-name)
       (%print-adapter-command-usage (find-adapter-or-die command-name)))
      (t
       (signal-cli-usage-error (format nil "Unknown command: ~A" command-name))))))

(defun print-cli-usage ()
  (format t "cl-py development CLI~%~%")
  (format t "Usage: sbcl --script scripts/dev-cli.lisp <command> [args]~%~%")
  (format t "Run `help <command>` for detailed usage of a native command group or adapter group.~%~%")
  (format t "Top-Level Commands:~%")
  (dolist (command (%sorted-top-level-cli-commands))
    (%print-command-entry (top-level-cli-command-usage command)
                          (top-level-cli-command-summary command)))
  (format t "~%Adapter Command Groups:~%")
  (dolist (adapter (%sorted-adapters))
    (%print-adapter-command-usage adapter)))

(defun %help-command-handler (args)
  (cond
    ((null args)
     (print-cli-usage))
    ((> (length args) 1)
     (signal-cli-usage-error "help accepts at most one command name"
                             (lambda ()
                               (format t "  help [command]~%"))))
    (t
     (print-command-help (first args)))))

(defun dispatch-top-level-command (args)
  (let* ((command-name (first args))
         (command-args (rest args))
         (top-level-command (%find-top-level-cli-command command-name)))
    (cond
      ((member command-name '("-h" "--help") :test #'string=)
       (print-cli-usage))
      (top-level-command
       (funcall (top-level-cli-command-handler top-level-command) command-args))
      ((cl-py:find-adapter command-name)
       (dispatch-adapter-command command-name command-args))
      (t
       (signal-cli-usage-error (format nil "Unknown command: ~A" command-name))))))

(defun dispatch-adapter-command (adapter-id rest)
  (cond
    ((null rest)
     (signal-cli-usage-error
      (format nil "Adapter ~A requires a subcommand" adapter-id)
      (%adapter-usage-printer adapter-id)))
    ((help-flag-p (first rest))
     (funcall (%adapter-usage-printer adapter-id)))
    ((string= (first rest) "metadata")
     (cl-py::%print-adapter-metadata adapter-id))
    ((string= (first rest) "version")
     (format t "~A~%" (cl-py:adapter-module-version adapter-id)))
    (t
     (let ((command (%find-cli-command adapter-id (first rest))))
       (if (null command)
           (signal-cli-usage-error
            (format nil "Unknown adapter subcommand: ~A ~A" adapter-id (first rest))
            (%adapter-usage-printer adapter-id))
           (let ((args (rest rest)))
             (if (< (length args) (cli-command-min-args command))
                 (signal-cli-usage-error
                  (format nil "Missing arguments for ~A ~A" adapter-id (cli-command-name command))
                  (%adapter-usage-printer adapter-id))
                 (apply (cli-command-handler command) args))))))))

(register-top-level-cli-command
 "help"
 #'%help-command-handler
 :usage "help [command]"
 :summary "Show top-level or command-specific usage"
 :detail-printer #'print-cli-usage)

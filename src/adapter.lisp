(in-package #:cl-py.internal)

(defstruct cli-command
  adapter-id
  name
  usage
  summary
  min-args
  handler)

(defparameter *cli-command-registry* nil)

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

(defun %print-adapter-command-usage (adapter)
  (format t "  ~A metadata~%" (adapter-id adapter))
  (format t "  ~A version~%" (adapter-id adapter))
  (dolist (command (%adapter-cli-commands (adapter-id adapter)))
    (format t "  ~A ~A~%" (adapter-id adapter) (cli-command-usage command))))

(defun print-cli-usage ()
  (format t "cl-py development CLI~%~%")
  (format t "Commands:~%")
  (format t "  registry~%")
  (cl-py::%print-json-usage)
  (cl-py::%print-time-usage)
  (dolist (adapter cl-py.internal:*adapter-registry*)
    (%print-adapter-command-usage adapter)))

(defun dispatch-adapter-command (adapter-id rest)
  (cond
    ((null rest)
     (print-cli-usage))
    ((string= (first rest) "metadata")
     (cl-py::%print-adapter-metadata adapter-id))
    ((string= (first rest) "version")
     (format t "~A~%" (cl-py:adapter-module-version adapter-id)))
    (t
     (let ((command (%find-cli-command adapter-id (first rest))))
       (if (null command)
           (print-cli-usage)
           (let ((args (rest rest)))
             (if (< (length args) (cli-command-min-args command))
                 (print-cli-usage)
                 (apply (cli-command-handler command) args))))))))

(in-package #:cl-py.internal)

(defun string-join (parts separator)
  (with-output-to-string (stream)
    (loop for part in parts
          for first = t then nil
          do (unless first
               (write-string separator stream))
             (write-string part stream))))

(defun %repo-python-command ()
  (let ((root (ignore-errors (asdf:system-source-directory "cl-py"))))
    (when root
      (let ((windows-python (merge-pathnames ".venv/Scripts/python.exe" root))
            (unix-python (merge-pathnames ".venv/bin/python" root)))
        (cond
          ((probe-file windows-python)
           (namestring (truename windows-python)))
          ((probe-file unix-python)
           (namestring (truename unix-python)))
          (t nil))))))

(defun %python-command ()
  (or (getenv "CL_PY_PYTHON")
      (%repo-python-command)
      "python"))

(defun %split-lines (text)
  (loop with start = 0
        for end = (position #\Newline text :start start)
        collect (string-trim '(#\Return #\Newline #\Space #\Tab)
                             (subseq text start end))
        while end
        do (setf start (1+ end))))

(defun %normalize-python-script (script)
  (with-output-to-string (stream)
    (loop with start = 0
          for marker = (search "~%" script :start2 start)
          do (if marker
                 (progn
                   (write-string script stream :start start :end marker)
                   (terpri stream)
                   (setf start (+ marker 2)))
                 (progn
                   (write-string script stream :start start)
                   (return))))))

(defun call-python-lines (script &rest args)
  (let ((command (append (list (%python-command)
                               "-c"
                               (%normalize-python-script script))
                         args)))
    (handler-case
        (let ((text (run-program command
                                 :output :string
                                 :error-output :output)))
          (remove "" (%split-lines text) :test #'string=))
      (error (condition)
        (error 'cl-py:python-execution-error
               :message "Python command failed"
               :command (string-join command " ")
               :output (princ-to-string condition))))))

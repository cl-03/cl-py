(in-package #:cl-py.internal)

(defun string-join (parts separator)
  (with-output-to-string (stream)
    (loop for part in parts
          for first = t then nil
          do (unless first
               (write-string separator stream))
             (write-string part stream))))

(defun %python-command ()
  (or (getenv "CL_PY_PYTHON")
      "python"))

(defun %split-lines (text)
  (loop with start = 0
        for end = (position #\Newline text :start start)
        collect (string-trim '(#\Return #\Newline #\Space #\Tab)
                             (subseq text start end))
        while end
        do (setf start (1+ end))))

(defun call-python-lines (script &rest args)
  (let ((command (append (list (%python-command) "-c" script) args)))
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

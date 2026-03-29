(in-package #:cl-py)

(defun normalize-packaging-version (value)
  (let ((lines (apply #'cl-py.internal:call-python-lines
                      "from packaging.version import Version~%import sys~%print(str(Version(sys.argv[1])))"
                      (list value))))
    (first lines)))

(cl-py.internal:register-cli-command
 "packaging"
 "normalize-version"
 #'normalize-packaging-version
 :usage "normalize-version <value>"
 :summary "Normalize a version string through packaging.version.Version"
 :min-args 1)
